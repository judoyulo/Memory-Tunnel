import SwiftUI

// MARK: - Conversation Timeline
//
// Bilateral timeline: left = you, right = them.
// Center line connects memories visually.
// Date section headers group by month.
// Newest at bottom (like iMessage), scroll to bottom on appear.

struct ConversationTimelineView: View {
    let memories: [Memory]
    let currentUserID: String?
    let onDelete: (Memory) -> Void

    @State private var selectedPhotoIndex: Int?

    private var photoMemories: [Memory] {
        memories.filter { $0.mediaType == "photo" }
    }

    /// Group memories by month for section headers
    private var sections: [(key: String, memories: [Memory])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: memories) { memory -> String in
            let date = memory.takenAt ?? memory.createdAt
            return formatter.string(from: date)
        }

        // Maintain chronological order (ASC from server)
        var seen = Set<String>()
        var result: [(key: String, memories: [Memory])] = []
        for memory in memories {
            let date = memory.takenAt ?? memory.createdAt
            let key = formatter.string(from: date)
            if !seen.contains(key) {
                seen.insert(key)
                result.append((key: key, memories: grouped[key] ?? []))
            }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections, id: \.key) { section in
                        // Date section header
                        dateSectionHeader(section.key)

                        ForEach(section.memories) { memory in
                            let isOwn = memory.ownerID == currentUserID
                            TimelineItemView(
                                memory: memory,
                                isOwn: isOwn,
                                onTapPhoto: {
                                    if memory.mediaType == "photo",
                                       let idx = photoMemories.firstIndex(where: { $0.id == memory.id }) {
                                        selectedPhotoIndex = idx
                                    }
                                },
                                onDelete: { onDelete(memory) }
                            )
                            .id(memory.id)
                        }
                    }
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, 80) // space for floating button
            }
            .onAppear {
                if let lastID = memories.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { selectedPhotoIndex.map { PhotoDetailItem(index: $0) } },
            set: { selectedPhotoIndex = $0?.index }
        )) { item in
            PhotoDetailView(memories: photoMemories, initialIndex: item.index)
        }
    }

    private func dateSectionHeader(_ title: String) -> some View {
        HStack {
            Spacer()
            Text(title)
                .font(.mtCaption)
                .foregroundStyle(Color.mtTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.mtBackground)
            Spacer()
        }
        .padding(.vertical, Spacing.md)
    }
}

private struct PhotoDetailItem: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Timeline Item (single memory positioned left or right)

struct TimelineItemView: View {
    let memory: Memory
    let isOwn: Bool
    let onTapPhoto: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !isOwn { Spacer(minLength: 0) }

            TimelineMemoryCard(
                memory: memory,
                onTapPhoto: onTapPhoto,
                onDelete: onDelete
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.55)

            if isOwn { Spacer(minLength: 0) }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 4)
        .background(
            // Center line segment
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.mtLabel.opacity(0.08))
                    .frame(width: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .frame(height: geo.size.height)
            }
        )
        .overlay(
            // Timeline dot at center
            Circle()
                .fill(Color.mtSurface)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.mtLabel.opacity(0.12), lineWidth: 1.5)
                )
            , alignment: .center
        )
    }
}
