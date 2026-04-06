import Foundation
import CoreGraphics

/// Positioned face bubble for rendering.
struct PositionedBubble: Identifiable {
    let id: UUID
    let suggestionIndex: Int
    var center: CGPoint
    var radius: CGFloat
}

/// Circle-packing layout engine for face bubbles.
/// Places largest bubble at center, packs subsequent bubbles closest-to-center without overlap.
/// O(n^2) with n<=30 completes in <1ms.
enum FaceBubbleLayout {

    /// Compute positions for bubbles given face counts and container size.
    /// - Parameters:
    ///   - counts: array of (index, photoCount) sorted by count descending
    ///   - containerSize: the available area
    ///   - minRadius: minimum bubble radius (44pt / 2 = 22pt for tap target)
    ///   - maxRadius: maximum bubble radius
    ///   - padding: space between bubbles
    static func layout(
        counts: [(index: Int, id: UUID, count: Int)],
        containerSize: CGSize,
        minRadius: CGFloat = 22,
        maxRadius: CGFloat = 60,
        padding: CGFloat = 4
    ) -> [PositionedBubble] {
        guard !counts.isEmpty else { return [] }

        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let maxCount = counts.map(\.count).max() ?? 1

        // Scale factor: sqrt scaling prevents one dominant face
        let scaleFactor: CGFloat = (maxRadius - minRadius) / CGFloat(sqrt(Double(maxCount)))

        var placed: [PositionedBubble] = []

        for item in counts {
            let radius = min(maxRadius, minRadius + CGFloat(sqrt(Double(item.count))) * scaleFactor)

            if placed.isEmpty {
                // First bubble goes at center
                placed.append(PositionedBubble(
                    id: item.id,
                    suggestionIndex: item.index,
                    center: center,
                    radius: radius
                ))
                continue
            }

            // Find position closest to center that doesn't overlap any existing bubble
            let position = findPosition(
                radius: radius,
                existing: placed,
                center: center,
                containerSize: containerSize,
                padding: padding
            )

            placed.append(PositionedBubble(
                id: item.id,
                suggestionIndex: item.index,
                center: position,
                radius: radius
            ))
        }

        return placed
    }

    /// Finds the closest-to-center position for a new circle without overlapping existing ones.
    private static func findPosition(
        radius: CGFloat,
        existing: [PositionedBubble],
        center: CGPoint,
        containerSize: CGSize,
        padding: CGFloat
    ) -> CGPoint {
        // Try positions at increasing distances from center, in a spiral pattern
        var bestPoint = CGPoint(x: center.x + radius * 3, y: center.y)
        var bestDistance = CGFloat.infinity

        let angleStep: CGFloat = .pi / 12  // 15 degree increments
        let distanceStep: CGFloat = 4      // 4pt increments outward

        for dist in stride(from: radius + padding, to: max(containerSize.width, containerSize.height), by: distanceStep) {
            for angleIndex in 0..<Int(2 * .pi / angleStep) {
                let angle = CGFloat(angleIndex) * angleStep
                let candidate = CGPoint(
                    x: center.x + dist * cos(angle),
                    y: center.y + dist * sin(angle)
                )

                // Check bounds (keep bubble fully inside container)
                guard candidate.x - radius >= 0,
                      candidate.x + radius <= containerSize.width,
                      candidate.y - radius >= 0,
                      candidate.y + radius <= containerSize.height else { continue }

                // Check overlap with all existing bubbles
                let overlaps = existing.contains { bubble in
                    let dx = candidate.x - bubble.center.x
                    let dy = candidate.y - bubble.center.y
                    let distance = sqrt(dx * dx + dy * dy)
                    return distance < (radius + bubble.radius + padding)
                }

                if !overlaps {
                    let distToCenter = sqrt(pow(candidate.x - center.x, 2) + pow(candidate.y - center.y, 2))
                    if distToCenter < bestDistance {
                        bestDistance = distToCenter
                        bestPoint = candidate
                    }
                    // Found a good one at this distance — stop checking more angles at same distance
                    // but keep checking closer distances
                    break
                }
            }

            // If we found something, and we've moved past it, stop
            if bestDistance < dist - distanceStep * 2 { break }
        }

        return bestPoint
    }
}
