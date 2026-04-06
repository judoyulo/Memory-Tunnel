// FaceEmbeddingService.swift
// On-device face identity service using MobileFaceNet CoreML model (w600k_mbf).
//
// Pipeline: Vision detects face + landmarks → affine alignment via eye centers
// → MobileFaceNet → 512-dim L2-normalized embedding → cosine similarity matching.
//
// Replaces FaceIndexService. Single source of truth for face identity.
//
// Privacy guarantees (enforced by architecture):
//   - All processing on-device (Vision + CoreML)
//   - Face records stored in app sandbox only (Application Support/face_embeddings.json)
//   - Embeddings never included in API payloads
//   - No biometric data transmitted to server

import CoreML
import Vision
import UIKit
import os.log

private let logger = Logger(subsystem: "com.memorytunnel.app", category: "FaceEmbedding")

// MARK: - FaceRecord

struct FaceRecord: Codable, Identifiable {
    let id: UUID
    /// 512-dim L2-normalized MobileFaceNet embedding.
    var embedding: [Float]
    var partnerID: String?
    var chapterID: String?
    let createdAt: Date
    /// JPEG face crop for the "Who is this?" prompt UI.
    var cropJPEG: Data?
}

// MARK: - FaceCandidate

struct FaceCandidate {
    let faceID: UUID
    let boundingBox: CGRect
    let crop: UIImage?
    let matchedPartnerID: String?
    /// Cosine similarity to best match. 1.0 = identical, higher = more similar.
    let matchSimilarity: Float
}

// MARK: - FaceEmbeddingService

actor FaceEmbeddingService {

    static let shared = FaceEmbeddingService()

    /// Cosine similarity threshold for "same person."
    static let matchThreshold: Float = 0.30

    /// Fixed merge threshold for post-clustering pass.
    static let mergeThreshold: Float = 0.25

    private var model: MLModel?
    private let store = FaceStore()

    private init() {}

    // MARK: - Public API (replaces FaceIndexService)

    /// Detect, embed, and match all faces in a photo.
    /// Call fire-and-forget after each successful memory upload.
    func processFaces(in image: UIImage) async -> [FaceCandidate] {
        guard let cgImage = image.cgImage else { return [] }

        let observations = await detectFaces(in: cgImage)
        guard !observations.isEmpty else { return [] }

        let allRecords = await store.all()
        var candidates: [FaceCandidate] = []

        for obs in observations {
            guard let result = await embedding(for: obs, in: cgImage) else { continue }

            let match = findBestMatch(result.embedding, in: allRecords)

            let candidateID: UUID
            if let match {
                candidateID = match.record.id
            } else {
                let newID = UUID()
                candidateID = newID
                let record = FaceRecord(
                    id: newID,
                    embedding: result.embedding,
                    partnerID: nil,
                    chapterID: nil,
                    createdAt: Date(),
                    cropJPEG: result.crop.jpegData(compressionQuality: 0.7)
                )
                try? await store.upsert(record)
            }

            candidates.append(FaceCandidate(
                faceID: candidateID,
                boundingBox: obs.boundingBox,
                crop: result.crop,
                matchedPartnerID: match?.record.partnerID,
                matchSimilarity: match?.similarity ?? 0
            ))
        }

        return candidates
    }

    /// Confirm an unrecognized face as a known chapter partner.
    func tag(faceID: UUID, as partnerID: String, in chapterID: String) async throws {
        let records = await store.all()
        guard var record = records.first(where: { $0.id == faceID }) else { return }
        record.partnerID = partnerID
        record.chapterID = chapterID
        try await store.upsert(record)
    }

    /// All untagged records, newest first. Drives the FaceTaggingBanner queue.
    func untaggedFaces() async -> [FaceRecord] {
        await store.untagged()
    }

    /// Store a face embedding directly for a chapter partner.
    /// Replaces any existing face record for this specific chapter only.
    func linkFaceToChapter(embedding: [Float], crop: UIImage?, partnerID: String, chapterID: String) async {
        // Only remove records for THIS specific chapter (not by partnerID — that could nuke other chapters)
        await store.removeRecords(forChapterID: chapterID)

        let record = FaceRecord(
            id: UUID(),
            embedding: embedding,
            partnerID: partnerID,
            chapterID: chapterID,
            createdAt: Date(),
            cropJPEG: crop?.jpegData(compressionQuality: 0.7)
        )
        try? await store.upsert(record)
    }

    /// Auto-link chapters to faces by scanning a photo from each chapter.
    /// Tries two approaches:
    ///   1. Download a chapter photo and detect the largest face
    ///   2. Fallback: use untagged face records from processFaces (already stored locally)
    func autoLinkChapters(chapters: [Chapter]) async {
        for chapter in chapters {
            let partnerID = chapter.partner?.id ?? chapter.id
            let existing = await store.all()
            if existing.contains(where: { $0.partnerID == partnerID || $0.chapterID == chapter.id }) {
                continue
            }

            logger.info("Auto-linking chapter \(chapter.id) (partner: \(partnerID))")

            // Approach 1: Download a chapter photo and detect faces
            var linked = false
            do {
                let memories = try await APIClient.shared.memories(chapterID: chapter.id)
                if let photoMemory = memories.last(where: { $0.mediaType == "photo" && $0.mediaURL != nil }),
                   let url = photoMemory.mediaURL {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data), let cgImage = image.cgImage {
                        let observations = await detectFaces(in: cgImage)
                        let sorted = observations.sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
                        for obs in sorted {
                            if let result = await embedding(for: obs, in: cgImage) {
                                await linkFaceToChapter(embedding: result.embedding, crop: result.crop, partnerID: partnerID, chapterID: chapter.id)
                                linked = true
                                logger.info("Auto-linked chapter \(chapter.id) via photo download")
                                break
                            }
                        }
                    }
                }
            } catch {
                logger.warning("Auto-link approach 1 failed for chapter \(chapter.id): \(error.localizedDescription)")
            }

            if !linked {
                logger.info("Auto-link: no face found for chapter \(chapter.id)")
            }
        }
    }

    /// Get the embedding for a specific partner (by partner ID or chapter ID).
    func embeddingForPartner(partnerID: String) async -> [Float]? {
        let all = await store.all()
        return all.first(where: { $0.partnerID == partnerID })?.embedding
    }

    /// Get the face record for a partner (includes crop JPEG).
    func faceRecordForPartner(partnerID: String) async -> FaceRecord? {
        let all = await store.all()
        return all.first(where: { $0.partnerID == partnerID })
    }

    func faceRecordForChapter(chapterID: String) async -> FaceRecord? {
        let all = await store.all()
        return all.first(where: { $0.chapterID == chapterID })
    }

    func embeddingForChapter(chapterID: String) async -> [Float]? {
        let all = await store.all()
        return all.first(where: { $0.chapterID == chapterID })?.embedding
    }

    // MARK: - Embedding Generation

    enum EmbeddingMethod { case aligned, unaligned }

    struct EmbeddingResult {
        let embedding: [Float]
        let crop: UIImage
        let method: EmbeddingMethod
    }

    /// Generate 512-dim embedding from a detected face.
    /// Tries alignment first; falls back to unaligned crop.
    func embedding(
        for observation: VNFaceObservation,
        in sourceImage: CGImage
    ) async -> EmbeddingResult? {
        guard let model = try? await loadModel() else { return nil }

        let imgW = CGFloat(sourceImage.width)
        let imgH = CGFloat(sourceImage.height)
        let box = observation.boundingBox

        // Reject tiny faces
        guard box.width * imgW >= 30, box.height * imgH >= 30 else { return nil }

        // Try aligned path (requires eye landmarks)
        if let lm = observation.landmarks,
           let le = lm.leftEye, le.pointCount >= 2,
           let re = lm.rightEye, re.pointCount >= 2 {
            let leftEye  = eyeCenter(le, box: box, imgW: imgW, imgH: imgH)
            let rightEye = eyeCenter(re, box: box, imgW: imgW, imgH: imgH)

            if let aligned = alignFace(source: sourceImage, leftEye: leftEye, rightEye: rightEye),
               let emb = await infer(model: model, image: aligned) {
                return EmbeddingResult(embedding: emb, crop: aligned, method: .aligned)
            }
        }

        // Fallback: unaligned crop
        guard let cropImage = cropFace(from: sourceImage, boundingBox: box) else { return nil }
        guard let emb = await infer(model: model, image: cropImage) else { return nil }
        return EmbeddingResult(embedding: emb, crop: cropImage, method: .unaligned)
    }

    /// Cosine similarity between two L2-normalized embeddings.
    nonisolated func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for i in 0 ..< a.count { dot += a[i] * b[i] }
        return dot
    }

    // MARK: - Face Detection

    func detectFaces(in cgImage: CGImage) async -> [VNFaceObservation] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceLandmarksRequest { req, _ in
                    continuation.resume(returning: (req.results as? [VNFaceObservation]) ?? [])
                }
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            }
        }
    }

    // MARK: - Eye Center Extraction

    private func eyeCenter(
        _ region: VNFaceLandmarkRegion2D,
        box: CGRect,
        imgW: CGFloat,
        imgH: CGFloat
    ) -> CGPoint {
        let pts = region.normalizedPoints
        let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
        let px = (box.origin.x + cx * box.width) * imgW
        let py = (1.0 - (box.origin.y + cy * box.height)) * imgH
        return CGPoint(x: px, y: py)
    }

    // MARK: - Face Alignment

    private static let refLeftEye  = CGPoint(x: 38.2946, y: 51.6963)
    private static let refRightEye = CGPoint(x: 73.5318, y: 51.5014)

    private func alignFace(source: CGImage, leftEye: CGPoint, rightEye: CGPoint) -> UIImage? {
        let refL = Self.refLeftEye
        let refR = Self.refRightEye

        let srcDx = rightEye.x - leftEye.x
        let srcDy = rightEye.y - leftEye.y
        let srcAngle = atan2(srcDy, srcDx)
        let srcDist = hypot(srcDx, srcDy)
        guard srcDist > 1 else { return nil }

        let refDist = hypot(refR.x - refL.x, refR.y - refL.y)
        let scale = refDist / srcDist

        var t = CGAffineTransform(translationX: refL.x, y: refL.y)
        t = t.scaledBy(x: scale, y: scale)
        t = t.rotated(by: -srcAngle)
        t = t.translatedBy(x: -leftEye.x, y: -leftEye.y)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 112, height: 112))
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.concatenate(t)
            UIImage(cgImage: source).draw(at: .zero)
        }
    }

    // MARK: - Face Cropping

    private func cropFace(from image: CGImage, boundingBox box: CGRect) -> UIImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(
            x: box.origin.x * w,
            y: (1 - box.origin.y - box.height) * h,
            width: box.width * w,
            height: box.height * h
        )
        let padded = rect
            .insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cropped = image.cropping(to: padded) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 112, height: 112))
        return renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: 112, height: 112))
        }
    }

    // MARK: - Model Inference

    private func infer(model: MLModel, image: UIImage) async -> [Float]? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 112, height: 112))
        let clean = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 112, height: 112))
        }
        guard let pb = clean.toPixelBuffer(width: 112, height: 112) else { return nil }
        do {
            let input = try MLDictionaryFeatureProvider(
                dictionary: ["faceImage": MLFeatureValue(pixelBuffer: pb)]
            )
            let out = try await model.prediction(from: input)
            guard let arr = out.featureValue(for: "embedding")?.multiArrayValue else { return nil }
            var v = [Float](repeating: 0, count: arr.count)
            for i in 0 ..< arr.count { v[i] = arr[i].floatValue }
            return l2Normalize(v)
        } catch {
            logger.error("Inference failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Matching

    private func findBestMatch(
        _ embedding: [Float],
        in records: [FaceRecord]
    ) -> (record: FaceRecord, similarity: Float)? {
        var best: (record: FaceRecord, similarity: Float)?

        for record in records {
            guard record.embedding.count == embedding.count else { continue }
            let sim = cosineSimilarity(embedding, record.embedding)
            if best == nil || sim > best!.similarity {
                best = (record, sim)
            }
        }

        guard let best, best.similarity >= Self.matchThreshold else { return nil }
        return best
    }

    // MARK: - Model Loading

    private func loadModel() async throws -> MLModel {
        if let model { return model }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        let m = try MobileFaceNet(configuration: cfg).model
        self.model = m
        return m
    }

    private func l2Normalize(_ v: [Float]) -> [Float] {
        var s: Float = 0
        for x in v { s += x * x }
        let n = s.squareRoot()
        guard n > 0 else { return v }
        return v.map { $0 / n }
    }
}

// MARK: - FaceStore

private actor FaceStore {
    private let url: URL
    private var cache: [UUID: FaceRecord]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        url = appSupport.appendingPathComponent("face_embeddings.json")
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)

        // Load existing data
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([FaceRecord].self, from: data) {
            cache = Dictionary(uniqueKeysWithValues: arr.map { ($0.id, $0) })
        } else {
            cache = [:]
        }

        // Clean up old landmark-based face index (incompatible format)
        let oldPath = appSupport.appendingPathComponent("face_index.json")
        if FileManager.default.fileExists(atPath: oldPath.path) {
            try? FileManager.default.removeItem(at: oldPath)
            logger.info("Deleted old landmark-based face_index.json")
        }
    }

    func all() -> [FaceRecord] { Array(cache.values) }

    func untagged() -> [FaceRecord] {
        cache.values.filter { $0.partnerID == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    func upsert(_ record: FaceRecord) throws {
        cache[record.id] = record
        try persist()
    }

    func removeRecords(forChapterID chapterID: String) {
        let toRemove = cache.values.filter { $0.chapterID == chapterID }.map(\.id)
        for id in toRemove { cache.removeValue(forKey: id) }
        try? persist()
    }

    func removeRecords(forPartnerID partnerID: String) {
        let toRemove = cache.values.filter { $0.partnerID == partnerID }.map(\.id)
        for id in toRemove { cache.removeValue(forKey: id) }
        try? persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Array(cache.values))
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - UIImage → CVPixelBuffer

extension UIImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let buf = pb else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cg = self.cgImage else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buf
    }
}
