import Vision
import UIKit

/// On-device face detection using Apple Vision framework (no network).
/// Called before the send flow to decide whether to prompt for face labeling.
final class FaceDetectionService {

    /// Returns the bounding boxes of detected faces, normalized to [0,1].
    static func detectFaces(in image: UIImage) async -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                // Vision coordinates: origin bottom-left; SwiftUI: top-left.
                // Return raw normalized rects — view layer handles coordinate flip.
                continuation.resume(returning: results.map(\.boundingBox))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Convenience: returns `true` if at least one face is detected.
    static func containsFace(in image: UIImage) async -> Bool {
        await !(detectFaces(in: image).isEmpty)
    }
}
