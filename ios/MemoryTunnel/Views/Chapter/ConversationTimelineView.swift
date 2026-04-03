import SwiftUI

// MARK: - Journal Timeline View
//
// Single-column memory journal. Metadata-first cards.
// Replaces the bilateral left/right "DM chat" layout.
// Date section headers group by month. Newest at bottom.

struct ConversationTimelineView: View {
    let memories: [Memory]
    let currentUserID: String?
    let partnerName: String?
    let onDelete: (Memory) -> Void
    let onEdit: (Memory) -> Void

    @State private var selectedPhotoIndex: Int?

    private var photoMemories: [Memory] {
        memories.filter { $0.mediaType == "photo" }
    }

    private var sections: [(key: String, memories: [Memory])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: memories) { memory -> String in
            let date = memory.displayDate
            return formatter.string(from: date)
        }

        var seen = Set<String>()
        var result: [(key: String, memories: [Memory])] = []
        for memory in memories {
            let date = memory.displayDate
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
                LazyVStack(spacing: Spacing.md) {
                    ForEach(sections, id: \.key) { section in
                        dateSectionHeader(section.key)

                        ForEach(section.memories) { memory in
                            JournalEntryCard(
                                memory: memory,
                                currentUserID: currentUserID,
                                partnerName: partnerName,
                                onTapPhoto: {
                                    if memory.mediaType == "photo",
                                       let idx = photoMemories.firstIndex(where: { $0.id == memory.id }) {
                                        selectedPhotoIndex = idx
                                    }
                                },
                                onEdit: { onEdit(memory) },
                                onDelete: { onDelete(memory) }
                            )
                            .id(memory.id)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, 80)
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
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mtTertiary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }
}

private struct PhotoDetailItem: Identifiable {
    let index: Int
    var id: Int { index }
}
