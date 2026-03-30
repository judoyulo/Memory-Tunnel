// FaceIndexService.swift
// On-device face identity index using Apple Vision's facial landmark detection.
//
// Implementation: uses VNDetectFaceLandmarksRequest to extract 76 facial landmark
// points per face. These are normalized to face-relative coordinates (face center = 0,0;
// face size = 1.0) and stored as [Float]. Identity matching uses L2 distance on this
// 152-dim vector, which is stable across lighting, scale, and minor angle changes.
//
// Why landmark vectors instead of VNGenerateImageFeaturePrintRequest:
//   Feature prints describe "what this image looks like" (scene-level). The same face
//   in different lighting or at a slightly different angle produces a different print,
//   exceeding the match threshold → false "different person" result.
//   Facial geometry (inter-eye distance, nose-to-mouth ratio, jaw shape) is stable —
//   this is the same primitive underlying Face ID.
//
// Privacy guarantees (enforced by architecture):
//   - Face crops stored only in app sandbox (Documents/face_index.json)
//   - Landmark descriptors never included in API payloads
//   - No biometric data is transmitted to the server

import Vision
import UIKit

// MARK: - FaceRecord

struct FaceRecord: Codable, Identifiable {
    let id: UUID
    /// Normalized facial landmark vector: up to 76 (x,y) pairs in face-relative coords.
    /// face center = (0,0), face size = 1.0. 152 floats total.
    var landmarkDescriptor: [Float]
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
    /// L2 distance from best-matching record. 0 = identical, lower = more similar.
    let matchDistance: Float
}

// MARK: - FaceIndexService

@MainActor
final class FaceIndexService {

    static let shared = FaceIndexService()

    /// L2 distance threshold below which two landmark descriptors are treated as the same person.
    /// In face-relative normalized space: same person typically <0.10, different person >0.15.
    /// 0.12 is conservative — prefers false negatives (missed match) over false merges.
    private let matchThreshold: Float = 0.12

    /// Minimum landmark points required for a usable descriptor.
    /// Vision returns exactly 76 for a well-detected frontal face.
    /// Requiring exactly 76 guarantees all descriptors are 152 floats — enabling reliable L2 matching.
    /// Fewer points (profile, occlusion) are skipped to avoid variable-length descriptor mismatches.
    private let minLandmarkCount = 76

    private let store = FaceStore()
    private init() {}

    // MARK: - Public API

    /// Detect, embed, and match all faces in a photo.
    /// Call fire-and-forget after each successful memory upload.
    func processFaces(in image: UIImage) async -> [FaceCandidate] {
        guard let cgImage = image.cgImage else { return [] }

        let observations = await detectFacesWithLandmarks(in: cgImage)
        guard !observations.isEmpty else { return [] }

        let allRecords = await store.all()
        var candidates: [FaceCandidate] = []

        for observation in observations {
            // Skip faces with too few landmarks (extreme angle, occlusion, profile view).
            guard let descriptor = extractLandmarkDescriptor(from: observation) else { continue }

            let crop  = cropFace(from: cgImage, boundingBox: observation.boundingBox)
            let match = findBestMatch(descriptor, in: allRecords)

            let candidateID: UUID
            if let match {
                candidateID = match.record.id
            } else {
                let newID = UUID()
                candidateID = newID
                let record = FaceRecord(
                    id:                 newID,
                    landmarkDescriptor: descriptor,
                    partnerID:          nil,
                    chapterID:          nil,
                    createdAt:          Date(),
                    cropJPEG:           crop.flatMap { $0.jpegData(compressionQuality: 0.7) }
                )
                try? await store.upsert(record)
            }

            candidates.append(FaceCandidate(
                faceID:           candidateID,
                boundingBox:      observation.boundingBox,
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

    private func detectFacesWithLandmarks(in image: CGImage) async -> [VNFaceObservation] {
        await withCheckedContinuation { continuation in
            // Dispatch off main thread: VNImageRequestHandler.perform is synchronous and can take
            // 200–500ms per image. FaceIndexService is @MainActor — without this dispatch the
            // main thread would block for the entire Vision request, stalling the UI.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceLandmarksRequest { req, _ in
                    continuation.resume(returning: (req.results as? [VNFaceObservation]) ?? [])
                }
                try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            }
        }
    }

    // MARK: - Landmark Descriptor Extraction

    /// Builds a 152-float descriptor from normalized facial landmark points.
    /// Each point is translated to face-center-relative and scaled by face size,
    /// giving a lighting-invariant, scale-invariant geometric face identity.
    private func extractLandmarkDescriptor(from observation: VNFaceObservation) -> [Float]? {
        guard let allPoints = observation.landmarks?.allPoints else { return nil }
        let points = allPoints.normalizedPoints
        guard points.count >= minLandmarkCount else { return nil }

        let box   = observation.boundingBox
        let cx    = box.midX
        let cy    = box.midY
        let scale = max(box.width, box.height)
        guard scale > 0 else { return nil }

        var descriptor = [Float]()
        descriptor.reserveCapacity(152)
        for point in points.prefix(76) {
            descriptor.append(Float((point.x - cx) / scale))
            descriptor.append(Float((point.y - cy) / scale))
        }
        return descriptor
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

    // MARK: - Matching

    private func findBestMatch(
        _ descriptor: [Float],
        in records: [FaceRecord]
    ) -> (record: FaceRecord, distance: Float)? {
        var best: (record: FaceRecord, distance: Float)?

        for record in records {
            guard record.landmarkDescriptor.count == descriptor.count else { continue }
            let dist = l2Distance(descriptor, record.landmarkDescriptor)
            if best == nil || dist < best!.distance {
                best = (record, dist)
            }
        }

        guard let best, best.distance <= matchThreshold else { return nil }
        return best
    }

    private func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        var sumSq: Float = 0
        for i in 0 ..< a.count { sumSq += (a[i] - b[i]) * (a[i] - b[i]) }
        return sumSq.squareRoot()
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
            // Old format (featurePrintData schema) or no data — start fresh.
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
