import SwiftUI
import AVFoundation

// MARK: - Timeline Memory Card
//
// Renders a memory in the conversation timeline.
// Switches on mediaType: photo, voice, text, location_checkin.

struct TimelineMemoryCard: View {
    let memory: Memory
    let onTapPhoto: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch memory.mediaType {
            case "photo":  photoCard
            case "voice":  voiceCard
            case "text":   textCard
            case "location_checkin": locationCard
            default: textCard
            }

            // Caption (photo/voice/location only, not text)
            if memory.mediaType != "text",
               let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }

            // Metadata row
            metadataRow
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Photo Card

    @ViewBuilder
    private var photoCard: some View {
        let photoHeight: CGFloat = {
            if let ratio = memory.aspectRatio {
                let width = UIScreen.main.bounds.width * 0.55 - 2 // card width minus border
                return min(width / ratio, 280)
            }
            return 200
        }()

        Button(action: onTapPhoto) {
            AsyncImage(url: memory.mediaURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.mtSurface
            }
            .frame(height: photoHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice Card

    @ViewBuilder
    private var voiceCard: some View {
        VoiceClipTileView(memory: memory)
            .padding(10)
    }

    // MARK: - Text Card

    @ViewBuilder
    private var textCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.caption ?? "")
                .font(.system(size: 16, design: .serif))
                .italic()
                .foregroundStyle(Color.mtLabel)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let tags = memory.emotionTags, !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mtSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.mtBackground)
                            .clipShape(Capsule())
                    }
                    if tags.count > 2 {
                        Text("+\(tags.count - 2)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mtTertiary)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Location Card

    @ViewBuilder
    private var locationCard: some View {
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
        .padding(12)
    }

    // MARK: - Metadata Row

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 4) {
            if let loc = memory.locationName {
                Image(systemName: "mappin")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mtTertiary)
                Text(loc)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mtTertiary)
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mtTertiary)
            }
            Text(timeAgoText)
                .font(.system(size: 11))
                .foregroundStyle(Color.mtTertiary)
            Spacer()
        }
    }

    private var timeAgoText: String {
        let date = memory.takenAt ?? memory.createdAt
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date, to: Date())
        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        if let days = components.day, days > 0 {
            return days == 1 ? "Yesterday" : "\(days) days ago"
        }
        return "Today"
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

            // Waveform visualization
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
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
        if let url = localAudioURL {
            play(url: url)
            return
        }
        guard let url = memory.mediaURL else { showError = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                // Expired URL — caller should refresh via refresh_url endpoint
                showError = true
                return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(memory.id)
                .appendingPathExtension("m4a")
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
