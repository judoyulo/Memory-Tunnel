// ShareCardSheet.swift
// Half-sheet card style picker for sharing feed photos off-app.
// Two styles: Time Capsule (time distance hero) and Excavation (depth number hero).
// 1080x1350 (4:5) format for maximum photo size on social. Share via UIActivityViewController.

import SwiftUI
import Photos
import AudioToolbox

// MARK: - Card Styles

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case timeCapsule = "Time Capsule"
    case excavation = "Excavation"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeCapsule: return "clock.arrow.circlepath"
        case .excavation:  return "arrow.down.to.line"
        }
    }

    var displayName: String {
        switch self {
        case .timeCapsule: return L.timeCapsule
        case .excavation:  return L.excavation
        }
    }
}

// MARK: - Time Unit Picker

enum TimeUnit: String, CaseIterable, Identifiable {
    case years = "yrs"
    case months = "mos"
    case days = "days"
    case hours = "hrs"
    case minutes = "min"
    case seconds = "sec"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .years:   return L.timeUnitYrs
        case .months:  return L.timeUnitMos
        case .days:    return L.timeUnitDays
        case .hours:   return L.timeUnitHrs
        case .minutes: return L.timeUnitMin
        case .seconds: return L.timeUnitSec
        }
    }

    func value(from date: Date) -> Int {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        switch self {
        case .years:   return Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        case .months:  return Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        case .days:    return Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        case .hours:   return Int(interval / 3600)
        case .minutes: return Int(interval / 60)
        case .seconds: return Int(interval)
        }
    }

    func label(from date: Date) -> String {
        let v = value(from: date)
        switch self {
        case .years:   return L.yearsAgo(v)
        case .months:  return L.monthsAgo(v)
        case .days:    return L.daysAgo(v)
        case .hours:   return L.hoursAgo(v)
        case .minutes: return L.minutesAgo(v)
        case .seconds: return L.secondsAgo(v)
        }
    }
}

// MARK: - Share Card Sheet

struct ShareCardSheet: View {
    let photo: UIImage
    let creationDate: Date?
    let locationName: String?
    let photoDepth: Int
    let asset: PHAsset

    @State private var selectedStyle: ShareCardStyle = .timeCapsule
    @State private var selectedUnit: TimeUnit = .years
    @State private var caption: String = ""
    @State private var renderedCards: [ShareCardStyle: UIImage] = [:]
    @State private var appeared = false
    @State private var savedToPhotos = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.mtTertiary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Live preview
                    if let rendered = renderedCards[selectedStyle] {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.md)
                            .scaleEffect(appeared ? 1.0 : 0.9)
                            .opacity(appeared ? 1.0 : 0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1), value: appeared)
                            .id(selectedStyle)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(Color.mtSurface)
                            .aspectRatio(4.0/5.0, contentMode: .fit)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.md)
                            .overlay { ProgressView() }
                    }

                    // Style picker (horizontal)
                    HStack(spacing: Spacing.md) {
                        ForEach(ShareCardStyle.allCases) { style in
                            Button {
                                withAnimation(.mtSpring) { selectedStyle = style }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: style.icon)
                                        .font(.system(size: 18))
                                    Text(style.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(selectedStyle == style ? Color.mtLabel : Color.mtTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selectedStyle == style
                                        ? Color.mtLabel.opacity(0.08)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(appeared ? 1.0 : 0.8)
                            .opacity(appeared ? 1.0 : 0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.75)
                                .delay(0.15 + Double(ShareCardStyle.allCases.firstIndex(of: style) ?? 0) * 0.08),
                                value: appeared
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.xl)

                    // Time unit picker (only for Time Capsule)
                    if selectedStyle == .timeCapsule, let date = creationDate {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TimeUnit.allCases) { unit in
                                    let v = unit.value(from: date)
                                    Button {
                                        withAnimation(.mtSpring) { selectedUnit = unit }
                                        renderCards()
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(v.formatted())
                                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                            Text(unit.displayLabel)
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundStyle(selectedUnit == unit ? Color.mtBackground : Color.mtSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedUnit == unit ? Color.mtLabel : Color.mtLabel.opacity(0.06))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Spacing.xl)
                        }
                    }

                    // Caption field
                    TextField(L.addALine, text: $caption)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mtLabel)
                        .padding(12)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .padding(.horizontal, Spacing.xl)
                        .onChange(of: caption) { _, _ in renderCards() }
                }
            }

            // Action buttons
            HStack(spacing: Spacing.md) {
                // Open in Photos
                Button {
                    openInPhotos()
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.mtLabel)
                        .frame(width: 48, height: 48)
                        .background(Color.mtSurface)
                        .clipShape(Circle())
                }

                // Save to camera roll
                Button {
                    saveToPhotos()
                } label: {
                    Image(systemName: savedToPhotos ? "checkmark" : "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(savedToPhotos ? Color.mtAccent : Color.mtLabel)
                        .frame(width: 48, height: 48)
                        .background(Color.mtSurface)
                        .clipShape(Circle())
                }

                // Share button (primary)
                Button {
                    shareCard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text(L.share.lowercased())
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.mtBackground)
        .onAppear {
            // Pick the most natural default unit based on photo age
            if let date = creationDate {
                let months = Calendar.current.dateComponents([.month], from: date, to: Date()).month ?? 0
                if months >= 12 { selectedUnit = .years }
                else if months >= 1 { selectedUnit = .months }
                else { selectedUnit = .days }
            }
            renderCards()
            withAnimation { appeared = true }
        }
    }

    // MARK: - Render

    private func renderCards() {
        let cap = caption.isEmpty ? nil : caption
        for style in ShareCardStyle.allCases {
            renderedCards[style] = ShareCardRenderer.render(
                style: style,
                photo: photo,
                creationDate: creationDate,
                locationName: locationName,
                photoDepth: photoDepth,
                caption: cap,
                timeUnit: selectedUnit
            )
        }
    }

    // MARK: - Actions

    private func shareCard() {
        guard let image = renderedCards[selectedStyle] else { return }

        // Haptic + shutter sound
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(1108)

        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(vc, animated: true)
        }
    }

    private func saveToPhotos() {
        guard let image = renderedCards[selectedStyle] else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.mtBounce) { savedToPhotos = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { savedToPhotos = false }
        }
    }

    private func openInPhotos() {
        let id = asset.localIdentifier
        if let url = URL(string: "photos-redirect://asset/\(id)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Card Renderer (1080x1350, 4:5 ratio)

enum ShareCardRenderer {

    // Card size: 1080x1350 (4:5) — max size on Instagram feed, great in iMessage
    private static let cardWidth: CGFloat = 1080
    private static let cardHeight: CGFloat = 1350

    static func render(
        style: ShareCardStyle,
        photo: UIImage,
        creationDate: Date?,
        locationName: String?,
        photoDepth: Int,
        caption: String?,
        timeUnit: TimeUnit = .years
    ) -> UIImage {
        switch style {
        case .timeCapsule: return renderTimeCapsule(photo: photo, date: creationDate, location: locationName, caption: caption, timeUnit: timeUnit)
        case .excavation:  return renderExcavation(photo: photo, depth: photoDepth, date: creationDate, location: locationName, caption: caption)
        }
    }

    // MARK: - Time Capsule
    //
    // Layout (1080x1350):
    //   [60px top margin]
    //   "3 years, 4 months ago"  (centered, 48pt)
    //   [24px gap]
    //   [PHOTO — fills width minus margins, 4:3 aspect = 960x720]
    //   [24px gap]
    //   "April 2023 · Barcelona" (centered, 30pt secondary)
    //   "caption if any"         (centered, 28pt italic)
    //   [spacer]
    //   "memory tunnel"          (bottom-right, 22pt, 25% opacity)

    private static func renderTimeCapsule(photo: UIImage, date: Date?, location: String?, caption: String?, timeUnit: TimeUnit) -> UIImage {
        let size = CGSize(width: cardWidth, height: cardHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            // Background: warm cream
            UIColor(red: 0.961, green: 0.918, blue: 0.847, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let margin: CGFloat = 60
            let centerPara = NSMutableParagraphStyle()
            centerPara.alignment = .center

            // Time distance text at top (user-selected unit)
            let timeText = date.map { timeUnit.label(from: $0) } ?? L.aWhileAgo
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .medium),
                .foregroundColor: UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 0.85),
                .paragraphStyle: centerPara
            ]
            let timeRect = CGRect(x: margin, y: margin, width: size.width - margin * 2, height: 64)
            (timeText as NSString).draw(in: timeRect, withAttributes: timeAttrs)

            // Photo — large, preserving aspect ratio, centered
            let photoTop: CGFloat = margin + 64 + 24
            let photoWidth = size.width - margin * 2
            // Use actual photo aspect ratio (capped between 3:4 and 16:9)
            let actualAspect = photo.size.width / photo.size.height
            let clampedAspect = min(max(actualAspect, 0.75), 1.78) // 3:4 to 16:9
            let photoHeight = photoWidth / clampedAspect
            let maxPhotoHeight = size.height - photoTop - 200 // Leave room for text below
            let finalPhotoHeight = min(photoHeight, maxPhotoHeight)
            let photoRect = CGRect(x: margin, y: photoTop, width: photoWidth, height: finalPhotoHeight)

            // Clip + draw
            ctx.cgContext.saveGState()
            UIBezierPath(roundedRect: photoRect, cornerRadius: 12).addClip()
            drawCenterCropped(photo, in: photoRect)
            ctx.cgContext.restoreGState()

            // Date + location below photo
            var textY = photoRect.maxY + 24
            var metaLine = ""
            if let date {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMMM yyyy"
                metaLine = fmt.string(from: date)
            }
            if let loc = location, !loc.isEmpty {
                metaLine = metaLine.isEmpty ? loc : "\(metaLine) · \(loc)"
            }
            if !metaLine.isEmpty {
                let metaAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 30, weight: .regular),
                    .foregroundColor: UIColor(red: 0.388, green: 0.388, blue: 0.400, alpha: 1),
                    .paragraphStyle: centerPara
                ]
                let metaRect = CGRect(x: margin, y: textY, width: size.width - margin * 2, height: 44)
                (metaLine as NSString).draw(in: metaRect, withAttributes: metaAttrs)
                textY += 44
            }

            // Caption (always additional line, never replaces date)
            if let caption, !caption.isEmpty {
                let capAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 28),
                    .foregroundColor: UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 0.6),
                    .paragraphStyle: centerPara
                ]
                let capRect = CGRect(x: margin, y: textY + 4, width: size.width - margin * 2, height: 44)
                (caption as NSString).draw(in: capRect, withAttributes: capAttrs)
            }

            // Watermark
            drawWatermark(in: size, light: false)
        }
    }

    // MARK: - Excavation
    //
    // Layout (1080x1350, dark):
    //   [48px top margin]
    //   [PHOTO — fills width minus margins, uses natural aspect, large]
    //   [28px gap]
    //   "tunneled from 4,327 photos deep" (centered, amber monospace)
    //   "April 2023"                       (centered, white 50%)
    //   "caption if any"                   (centered, white 60% italic)
    //   [spacer]
    //   "memory tunnel"                    (bottom-right)

    private static func renderExcavation(photo: UIImage, depth: Int, date: Date?, location: String?, caption: String?) -> UIImage {
        let size = CGSize(width: cardWidth, height: cardHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            // Background: near-black
            UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let margin: CGFloat = 48
            let centerPara = NSMutableParagraphStyle()
            centerPara.alignment = .center

            // Photo — large, natural aspect ratio
            let photoTop: CGFloat = margin
            let photoWidth = size.width - margin * 2
            let actualAspect = photo.size.width / photo.size.height
            let clampedAspect = min(max(actualAspect, 0.75), 1.78)
            let photoHeight = photoWidth / clampedAspect
            let maxPhotoHeight = size.height - photoTop - 240
            let finalPhotoHeight = min(photoHeight, maxPhotoHeight)
            let photoRect = CGRect(x: margin, y: photoTop, width: photoWidth, height: finalPhotoHeight)

            ctx.cgContext.saveGState()
            UIBezierPath(roundedRect: photoRect, cornerRadius: 12).addClip()
            drawCenterCropped(photo, in: photoRect)
            ctx.cgContext.restoreGState()

            // Depth text
            let depthNum = max(depth, 1)
            let depthText = L.tunneledFrom(depthNum)
            let depthAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor(red: 0.784, green: 0.584, blue: 0.424, alpha: 1),
                .paragraphStyle: centerPara
            ]
            var textY = photoRect.maxY + 28
            let depthRect = CGRect(x: margin, y: textY, width: size.width - margin * 2, height: 40)
            (depthText as NSString).draw(in: depthRect, withAttributes: depthAttrs)
            textY += 44

            // Date + location (always shown, caption doesn't replace it)
            var metaLine = ""
            if let date {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMMM yyyy"
                metaLine = fmt.string(from: date)
            }
            if let loc = location, !loc.isEmpty {
                metaLine = metaLine.isEmpty ? loc : "\(metaLine) · \(loc)"
            }
            if !metaLine.isEmpty {
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.5),
                    .paragraphStyle: centerPara
                ]
                let dateRect = CGRect(x: margin, y: textY, width: size.width - margin * 2, height: 38)
                (metaLine as NSString).draw(in: dateRect, withAttributes: dateAttrs)
                textY += 40
            }

            // Caption (additional line, never replaces date)
            if let caption, !caption.isEmpty {
                let capAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 26),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                    .paragraphStyle: centerPara
                ]
                let capRect = CGRect(x: margin, y: textY + 4, width: size.width - margin * 2, height: 40)
                (caption as NSString).draw(in: capRect, withAttributes: capAttrs)
            }

            // Watermark
            drawWatermark(in: size, light: true)
        }
    }

    // MARK: - Helpers

    private static func drawCenterCropped(_ image: UIImage, in rect: CGRect) {
        guard let cgImage = image.cgImage else { return }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let targetAspect = rect.width / rect.height
        let imgAspect = imgW / imgH

        let drawRect: CGRect
        if imgAspect > targetAspect {
            // Image wider than target: crop sides
            let scaledH = rect.height
            let scaledW = imgAspect * scaledH
            drawRect = CGRect(
                x: rect.minX + (rect.width - scaledW) / 2,
                y: rect.minY,
                width: scaledW,
                height: scaledH
            )
        } else {
            // Image taller than target: crop top/bottom
            let scaledW = rect.width
            let scaledH = scaledW / imgAspect
            drawRect = CGRect(
                x: rect.minX,
                y: rect.minY + (rect.height - scaledH) / 2,
                width: scaledW,
                height: scaledH
            )
        }
        UIImage(cgImage: cgImage).draw(in: drawRect)
    }

    private static func drawWatermark(in size: CGSize, light: Bool) {
        let margin: CGFloat = 60
        let color: UIColor = light
            ? UIColor.white.withAlphaComponent(0.25)
            : UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 0.25)
        let wmAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: color
        ]
        let wmText = "memory tunnel"
        let wmSize = (wmText as NSString).size(withAttributes: wmAttrs)
        (wmText as NSString).draw(
            at: CGPoint(x: size.width - margin - wmSize.width, y: size.height - 52),
            withAttributes: wmAttrs
        )
    }
}
