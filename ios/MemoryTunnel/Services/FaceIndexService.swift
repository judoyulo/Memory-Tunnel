// FaceIndexService.swift
// On-device face identity index using Apple Vision's built-in feature extraction.
//
// Implementation note: uses VNGenerateImageFeaturePrintRequest (iOS 13+) on face crops
// rather than a separate bundled .mlpackage. Vision's internal model produces a
// feature vector per crop; similarity is computed via VNFeaturePrintObservation.computeDistance.
// This eliminates the 5MB model bundle while using the same on-device privacy guarantee.
//
// Privacy guarantees (enforced by architecture):
//   - Face crops stored only in app sandbox (Documents/face_index.json)
//   - Feature print data never included in API payloads
//   - No biometric data is transmitted to the server

import Vision
import UIKit

// MARK: - FaceRecord

struct FaceRecord: Codable, Identifiable {
    let id: UUID
    /// NSKeyedArchiver-serialized VNFeaturePrintObservation for similarity comparison.
    var featurePrintData: Data
    var partnerID: String?       // nil = untagged
    var chapterID: String?
    let createdAt: Date
    /// JPEG face crop (20% padding) for the "Who is this?" prompt UI.
    var cropJPEG: Data?
}

// MARK: - FaceCandidate

struct FaceCandidate {
    let faceID: UUID
    /// Vision-normalised bounding box (origin: bottom-left, values in [0,1]).
    let boundingBox: CGRect
    let crop: UIImage?
    let matchedPartnerID: String?
    /// Distance from best-matching record. 0 = identical, lower = more similar.
    let matchDistance: Float
}

// MARK: - FaceIndexService

@MainActor
final class FaceIndexService {

    static let shared = FaceIndexService()

    /// Distance threshold below which two face crops are treated as the same person.
    /// VNFeaturePrintObservation distances are typically <0.3 for the same face,
    /// >0.5 for different faces. 0.4 is a conservative midpoint.
    private let matchThreshold: Float = 0.4

    private let store = FaceStore()
    private init() {}

    // MARK: - Public API

    /// Detect, embed, and match all faces in a photo.
    /// Call fire-and-forget after each successful memory upload.
    func processFaces(in image: UIImage) async -> [FaceCandidate] {
        guard let cgImage = image.cgImage else { return [] }

        let boxes = await detectFaceBoxes(in: cgImage)
        guard !boxes.isEmpty else { return [] }

        let allRecords = await store.all()
        var candidates: [FaceCandidate] = []

        for box in boxes {
            let crop        = cropFace(from: cgImage, boundingBox: box)
            let observation: VNFeaturePrintObservation?
            if let crop { observation = await generateFeaturePrint(for: crop) }
            else        { observation = nil }

            let match = observation.flatMap { findBestMatch($0, in: allRecords) }

            let candidateID: UUID
            if let match {
                candidateID = match.record.id
            } else {
                let newID = UUID()
                candidateID = newID
                if let obs = observation,
                   let data = try? NSKeyedArchiver.archivedData(
                       withRootObject: obs, requiringSecureCoding: true) {
                    let record = FaceRecord(
                        id:               newID,
                        featurePrintData: data,
                        partnerID:        nil,
                        chapterID:        nil,
                        createdAt:        Date(),
                        cropJPEG:         crop.flatMap { $0.jpegData(compressionQuality: 0.7) }
                    )
                    try? await store.upsert(record)
                }
            }

            candidates.append(FaceCandidate(
                faceID:           candidateID,
                boundingBox:      box,
                crop:             crop,
                matchedPartnerID: match?.record.partnerID,
                matchDistance:    match?.distance ?? .infinity
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

    // MARK: - Face Detection

    private func detectFaceBoxes(in image: CGImage) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { req, _ in
                let boxes = (req.results as? [VNFaceObservation])?.map(\.boundingBox) ?? []
                continuation.resume(returning: boxes)
            }
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }

    // MARK: - Face Cropping

    private func cropFace(from image: CGImage, boundingBox box: CGRect) -> UIImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Vision: bottom-left origin. CGImage: top-left origin — flip Y.
        let rect = CGRect(x: box.origin.x * w,
                          y: (1 - box.origin.y - box.height) * h,
                          width:  box.width  * w,
                          height: box.height * h)
        let padded = rect
            .insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: padded).map(UIImage.init)
    }

    // MARK: - Feature Print Generation

    private func generateFeaturePrint(for image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { req, _ in
                continuation.resume(returning: req.results?.first as? VNFeaturePrintObservation)
            }
            request.imageCropAndScaleOption = .centerCrop
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    // MARK: - Matching

    private func findBestMatch(
        _ observation: VNFeaturePrintObservation,
        in records: [FaceRecord]
    ) -> (record: FaceRecord, distance: Float)? {
        var best: (record: FaceRecord, distance: Float)?

        for record in records {
            guard let archived = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: record.featurePrintData
            ) else { continue }

            var distance: Float = 0
            guard (try? observation.computeDistance(&distance, to: archived)) != nil else { continue }

            if best == nil || distance < best!.distance {
                best = (record, distance)
            }
        }

        guard let best, best.distance <= matchThreshold else { return nil }
        return best
    }
}

// MARK: - FaceStore

private actor FaceStore {
    private let url: URL
    private var cache: [UUID: FaceRecord]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("face_index.json")
        if let data = try? Data(contentsOf: url),
           let arr  = try? JSONDecoder().decode([FaceRecord].self, from: data) {
            cache = Dictionary(uniqueKeysWithValues: arr.map { ($0.id, $0) })
        } else {
            cache = [:]
        }
    }

    func all() -> [FaceRecord] { Array(cache.values) }

    func untagged() -> [FaceRecord] {
        cache.values.filter { $0.partnerID == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    func upsert(_ record: FaceRecord) throws {
        cache[record.id] = record
        let data = try JSONEncoder().encode(Array(cache.values))
        try data.write(to: url, options: .atomic)
    }
}
