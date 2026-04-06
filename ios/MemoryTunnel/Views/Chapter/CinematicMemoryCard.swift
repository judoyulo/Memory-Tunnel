import SwiftUI
import AVFoundation

// MARK: - Cinematic Memory Card
//
// Film-strip card renderer. Each content type gets its own
// cinematic personality within the same vertical scroll.
// Photo: full-bleed image with gradient metadata overlay.
// Text: centered italic typography on warm surface.
// Voice: waveform with inline playback.
// Location: map pin on warm surface.

struct CinematicMemoryCard: View {
    let memory: Memory
    let isHero: Bool
    let availableHeight: CGFloat
    let currentUserID: String?
    let partnerName: String?
    let onTapPhoto: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    // MARK: - Card Heights (proportional to available space, not screen)

    static func cardHeight(for mediaType: String, in availableHeight: CGFloat) -> CGFloat {
        // Sized so center (1.0x) + 2 above + 2 below all fit on screen
        // Center: ~35% of screen. Non-center at 0.4x scale = ~14% each.
        // 35% + 4 * 14% = 91% of screen = 5 cards visible
        switch mediaType {
        case "photo":           return availableHeight * 0.35
        case "text":            return availableHeight * 0.28
        case "voice":           return availableHeight * 0.24
        case "location_checkin": return availableHeight * 0.20
        default:                return availableHeight * 0.28
        }
    }

    private var cardHeight: CGFloat {
        Self.cardHeight(for: memory.mediaType, in: availableHeight)
    }

    var body: some View {
        cardContent
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch memory.mediaType {
        case "photo":           photoCard
        case "voice":           voiceCard
        case "text":            nonInteractiveCard { textCardBody }
        case "location_checkin": nonInteractiveCard { locationCardBody }
        default:                nonInteractiveCard { textCardBody }
        }
    }

    // Non-interactive cards get context menu directly
    private func nonInteractiveCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .contextMenu {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let type = memory.mediaType.replacingOccurrences(of: "_", with: " ")
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateStr = formatter.string(from: memory.displayDate)
        let location = memory.locationName ?? ""
        let caption = memory.caption ?? ""
        return [type.capitalized, dateStr, location, caption]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // MARK: - Photo Card

    @ViewBuilder
    private var photoCard: some View {
        Button(action: onTapPhoto) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: memory.mediaURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.mtSurface
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.mtTertiary)
                                    Text("Tap to reload")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.mtTertiary)
                                }
                            }
                    case .empty:
                        Color.mtSurface
                            .overlay {
                                ProgressView()
                                    .tint(Color.mtTertiary)
                            }
                    @unknown default:
                        Color.mtSurface
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight)
                .clipped()

                if isHero {
                    photoMetadataOverlay
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: cardHeight)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var photoMetadataOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: cardHeight * 0.35)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if let loc = memory.locationName, !loc.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(loc)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                }

                if let caption = memory.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Text Card

    @ViewBuilder
    private var textCardBody: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                Text("\u{201C}")
                    .font(.system(size: 48, design: .serif))
                    .foregroundStyle(Color.mtAccent.opacity(0.4))
                    .padding(.bottom, -20)

                Text(memory.caption ?? "")
                    .font(.system(size: 18).italic())
                    .foregroundStyle(Color.mtLabel)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()

            metadataFooter
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(Color.mtSurface)
    }

    // MARK: - Voice Card
    // Uses dedicated CinematicVoicePlayer with large tap target
    // to avoid gesture conflicts with scrollTransition.

    @ViewBuilder
    private var voiceCard: some View {
        // NO contextMenu on this card — it swallows child button taps.
        // Edit/delete is available via long-press on the footer area only.
        VStack(spacing: 0) {
            Spacer()

            CinematicVoicePlayer(memory: memory)

            if let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer()

            // Footer with context menu for edit/delete
            metadataFooter
                .contextMenu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(Color.mtSurface)
    }

    // MARK: - Location Card

    @ViewBuilder
    private var locationCardBody: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.mtSecondary)

                Text(memory.locationName ?? "Somewhere")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.mtLabel)

                if let caption = memory.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            metadataFooter
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(Color.mtSurface)
    }

    // MARK: - Shared footer

    private var metadataFooter: some View {
        HStack {
            Text(dateText)
                .font(.system(size: 12))
                .foregroundStyle(Color.mtTertiary)
            Spacer()
            Text(senderLabel)
                .font(.system(size: 12))
                .foregroundStyle(Color.mtTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .opacity(isHero ? 1 : 0)
    }

    // MARK: - Helpers

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: memory.displayDate)
    }

    private var senderLabel: String {
        let isOwn = memory.ownerID == currentUserID
        if isOwn { return "— You" }
        return "— \(partnerName ?? "them")"
    }
}

// MARK: - Cinematic Voice Player
//
// Large play button + stable waveform. Uses onTapGesture on a big
// hit area so it works reliably inside scrollTransition transforms.

struct CinematicVoicePlayer: View {
    let memory: Memory
    @State private var isPlaying = false
    @State private var localAudioURL: URL?
    @State private var player: AVAudioPlayer?
    @State private var isLoading = false
    @State private var showError = false

    // Stable waveform heights derived from memory ID (computed once)
    private var barHeights: [CGFloat] {
        let seed = abs(memory.id.hash)
        return (0..<20).map { i in
            CGFloat(((seed / (i + 1)) % 30) + 8)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Large play/pause button — Button has higher gesture priority than contextMenu
            Button {
                if isPlaying {
                    stopPlayback()
                } else {
                    Task { await downloadAndPlay() }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.mtLabel)
                        .frame(width: 64, height: 64)

                    if isLoading {
                        ProgressView()
                            .tint(Color.mtBackground)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.mtBackground)
                    }
                }
                .frame(width: 80, height: 80)
            }
            .buttonStyle(.plain)

            // Waveform bars
            HStack(spacing: 3) {
                ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isPlaying ? Color.mtLabel : Color.mtSecondary.opacity(0.4))
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 40)
            .animation(.easeOut(duration: 0.2), value: isPlaying)

            // Status text
            if showError {
                Text("Tap to retry")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtError)
            } else {
                Text(isPlaying ? "Playing..." : "Voice clip")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private func downloadAndPlay() async {
        showError = false

        if let url = localAudioURL {
            play(url: url)
            return
        }

        guard let url = memory.mediaURL else {
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                showError = true
                return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(memory.id).appendingPathExtension("m4a")
            try data.write(to: tmp)
            localAudioURL = tmp
            play(url: tmp)
        } catch {
            showError = true
        }
    }

    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            isPlaying = true
        } catch {
            showError = true
        }
    }

    private func stopPlayback() {
        player?.stop()
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
