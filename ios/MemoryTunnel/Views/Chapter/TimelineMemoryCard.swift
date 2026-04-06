import SwiftUI
import AVFoundation

// MARK: - Journal Entry Card
//
// Metadata-first memory card for the journal timeline.
// Date + location = hero. Photo = thumbnail. Caption = body.
// Tags + sender = footer.

struct JournalEntryCard: View {
    let memory: Memory
    let currentUserID: String?
    let partnerName: String?
    let onTapPhoto: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Date + Location (hero metadata)
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtLabel)

                if let loc = memory.locationName, !loc.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(loc)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mtSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .background(Color.mtLabel.opacity(0.08))

            // MARK: Content
            switch memory.mediaType {
            case "photo":  photoContent
            case "voice":  voiceContent
            case "text":   textContent
            case "location_checkin": locationContent
            default: textContent
            }

            // MARK: Tags + Sender footer
            HStack(alignment: .bottom) {
                // Tags
                if let tags = memory.emotionTags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.mtSecondary)
                        }
                    }
                }
                Spacer()
                // Sender
                Text(senderLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mtTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(alignment: .leading) {
            // Sender color bar: accent for partner, label for you
            let isOwn = memory.ownerID == currentUserID
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(isOwn ? Color.mtLabel.opacity(0.15) : Color.mtAccent.opacity(0.4))
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .onLongPressGesture { onEdit() }
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Date text

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: memory.displayDate)
    }

    // MARK: - Sender label

    private var senderLabel: String {
        let isOwn = memory.ownerID == currentUserID
        if isOwn { return "— You" }
        return "— \(partnerName ?? "them")"
    }

    // MARK: - Photo (prominent image with overlay metadata)

    @ViewBuilder
    private var photoContent: some View {
        Button(action: onTapPhoto) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: memory.mediaURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.mtSurface
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()

                // Gradient + caption overlay (only if caption exists)
                if let caption = memory.caption, !caption.isEmpty {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.5)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Text(caption)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice

    @ViewBuilder
    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            VoiceClipTileView(memory: memory)

            if let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Text (warm tinted background for visual distinction)

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\u{201C}") // opening quote mark
                .font(.system(size: 32, design: .serif))
                .foregroundStyle(Color.mtAccent.opacity(0.4))
                .padding(.bottom, -16)

            Text(memory.caption ?? "")
                .font(.system(size: 17, design: .serif))
                .italic()
                .foregroundStyle(Color.mtLabel)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Location check-in

    @ViewBuilder
    private var locationContent: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.mtSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.locationName ?? "Somewhere")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                if let caption = memory.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Voice Clip Tile (inline playback)

struct VoiceClipTileView: View {
    let memory: Memory
    @State private var isPlaying = false
    @State private var localAudioURL: URL?
    @State private var player: AVAudioPlayer?
    @State private var showError = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.mtSecondary)
                Text("Voice clip")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
                Spacer()

                if showError {
                    Button("Retry") { Task { await downloadAndPlay() } }
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtLabel)
                } else {
                    Button {
                        if isPlaying { stopPlayback() } else { Task { await downloadAndPlay() } }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(Color.mtLabel)
                    }
                }
            }

            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPlaying ? Color.mtAccent : Color.mtSecondary.opacity(0.4))
                        .frame(width: 3, height: CGFloat.random(in: 8...28))
                }
            }
            .frame(height: 32)
        }
    }

    private func downloadAndPlay() async {
        showError = false
        if let url = localAudioURL { play(url: url); return }
        guard let url = memory.mediaURL else { showError = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                showError = true; return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(memory.id).appendingPathExtension("m4a")
            try data.write(to: tmp)
            localAudioURL = tmp
            play(url: tmp)
        } catch { showError = true }
    }

    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            isPlaying = true
        } catch { showError = true }
    }

    private func stopPlayback() {
        player?.stop()
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
