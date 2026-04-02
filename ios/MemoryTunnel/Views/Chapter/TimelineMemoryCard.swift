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
        // Prefer event_date, then taken_at, then created_at
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        if let eventDateStr = memory.eventDate {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            if let parsed = parser.date(from: eventDateStr) {
                return formatter.string(from: parsed)
            }
        }
        return formatter.string(from: memory.takenAt ?? memory.createdAt)
    }

    // MARK: - Sender label

    private var senderLabel: String {
        let isOwn = memory.ownerID == currentUserID
        if isOwn { return "— You" }
        return "— \(partnerName ?? "them")"
    }

    // MARK: - Photo (thumbnail + caption side by side)

    @ViewBuilder
    private var photoContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onTapPhoto) {
                AsyncImage(url: memory.mediaURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.mtBackground
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    // MARK: - Text

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.caption ?? "")
                .font(.system(size: 16, design: .serif))
                .italic()
                .foregroundStyle(Color.mtLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

// VoiceClipTileView is defined in the original file and reused here
