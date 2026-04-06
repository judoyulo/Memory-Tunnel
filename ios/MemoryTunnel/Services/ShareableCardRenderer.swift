// ShareableCardRenderer.swift
// Renders shareable memory cards for Instagram Stories and iMessage.
//
// Format 1: Story Card (9:16 vertical, 1080x1920)
//   - Edge-to-edge photo (DESIGN.md compliant, no frames)
//   - Bottom gradient overlay: clear at 65% → black 55% at bottom
//   - Person name, date, location over gradient
//   - Optional message
//   - Memory Tunnel wordmark (subtle, bottom-right)
//
// Export as high-res PNG via UIGraphicsImageRenderer.

import UIKit

enum ShareableCardRenderer {

    // MARK: - Story Card (9:16)

    /// Render a 1080x1920 Story Card ready for Instagram Stories or iMessage.
    static func renderStoryCard(
        photo: UIImage,
        personName: String,
        date: Date?,
        locationName: String?,
        message: String? = nil
    ) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Edge-to-edge photo (fill, center-crop)
            drawCenterCropped(photo, in: CGRect(origin: .zero, size: size), context: cgCtx)

            // 2. Bottom gradient overlay: clear at 65% → rgba(0,0,0,0.55) at bottom
            let gradientColors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.55).cgColor]
            let gradientLocations: [CGFloat] = [0.0, 1.0]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors as CFArray,
                locations: gradientLocations
            ) {
                let gradientStart = CGPoint(x: size.width / 2, y: size.height * 0.65)
                let gradientEnd = CGPoint(x: size.width / 2, y: size.height)
                cgCtx.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
            }

            // 3. Text content over gradient
            let leftMargin: CGFloat = 48
            let rightMargin: CGFloat = 48
            let maxWidth = size.width - leftMargin - rightMargin
            var yPos = size.height - 180 // Start from bottom, work up

            // Message (if present)
            if let message, !message.isEmpty {
                let msgAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 42, weight: .regular),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.90)
                ]
                let msgRect = CGRect(x: leftMargin, y: yPos - 60, width: maxWidth, height: 60)
                (message as NSString).draw(in: msgRect, withAttributes: msgAttrs)
                yPos -= 80
            }

            // Date + location
            var dateLine = ""
            if let date {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMMM yyyy"
                dateLine = fmt.string(from: date)
            }
            if let loc = locationName, !loc.isEmpty {
                dateLine = dateLine.isEmpty ? loc : "\(dateLine) · \(loc)"
            }
            if !dateLine.isEmpty {
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .regular),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.70)
                ]
                let dateRect = CGRect(x: leftMargin, y: yPos - 50, width: maxWidth, height: 50)
                (dateLine as NSString).draw(in: dateRect, withAttributes: dateAttrs)
                yPos -= 60
            }

            // Person name
            if !personName.isEmpty {
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                ]
                let nameRect = CGRect(x: leftMargin, y: yPos - 60, width: maxWidth, height: 60)
                (personName as NSString).draw(in: nameRect, withAttributes: nameAttrs)
            }

            // 4. Memory Tunnel wordmark (bottom-right, subtle)
            let wmAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.40)
            ]
            let wmText = "Memory Tunnel"
            let wmSize = (wmText as NSString).size(withAttributes: wmAttrs)
            let wmX = size.width - rightMargin - wmSize.width
            let wmY = size.height - 60
            (wmText as NSString).draw(at: CGPoint(x: wmX, y: wmY), withAttributes: wmAttrs)
        }
    }

    // MARK: - Private

    /// Draw an image center-cropped to fill the target rect.
    private static func drawCenterCropped(_ image: UIImage, in rect: CGRect, context: CGContext) {
        guard let cgImage = image.cgImage else { return }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let targetAspect = rect.width / rect.height
        let imgAspect = imgW / imgH

        let drawRect: CGRect
        if imgAspect > targetAspect {
            // Image is wider: crop sides
            let scaledH = rect.height
            let scaledW = imgAspect * scaledH
            drawRect = CGRect(x: (rect.width - scaledW) / 2, y: 0, width: scaledW, height: scaledH)
        } else {
            // Image is taller: crop top/bottom
            let scaledW = rect.width
            let scaledH = scaledW / imgAspect
            drawRect = CGRect(x: 0, y: (rect.height - scaledH) / 2, width: scaledW, height: scaledH)
        }

        // UIGraphicsImageRenderer context has top-left origin (UIKit), so draw directly
        UIImage(cgImage: cgImage).draw(in: drawRect)
    }
}
