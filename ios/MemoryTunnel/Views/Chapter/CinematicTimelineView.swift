import SwiftUI

// MARK: - Cinematic Timeline View
//
// Vertical film strip. Center memory is hero (scale 1.0, full opacity).
// Flanking memories shrink dramatically with blur and 3D rotation.
// scrollTransition drives the effect. PreferenceKey detects
// the center card for seasonal tint + hero metadata overlay.

struct CinematicTimelineView: View {
    let memories: [Memory]
    let currentUserID: String?
    let partnerName: String?
    let onDelete: (Memory) -> Void
    let onEdit: (Memory) -> Void

    @State private var centerMemoryID: String?
    @State private var scrolledToID: String?
    @State private var scrollProgress: CGFloat = 0
    @State private var selectedPhotoIndex: Int?
    private var photoMemories: [Memory] {
        memories.filter { $0.mediaType == "photo" }
    }

    private var centerMemoryDate: Date? {
        guard let id = centerMemoryID else {
            return memories.last?.displayDate
        }
        return memories.first(where: { $0.id == id })?.displayDate
    }

    var body: some View {
        GeometryReader { outerGeo in
            let availableHeight = outerGeo.size.height

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(memories) { memory in
                            CinematicCardWrapper(
                                memory: memory,
                                isHero: memory.id == centerMemoryID,
                                availableHeight: availableHeight,
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
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.md)
                }
                .scrollPosition(id: $scrolledToID)
                .contentMargins(.vertical, availableHeight * 0.3, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .coordinateSpace(name: "cinematicScroll")
                .onChange(of: scrolledToID) { _, newID in
                    guard let newID else { return }
                    centerMemoryID = newID
                    if memories.count > 1,
                       let idx = memories.firstIndex(where: { $0.id == newID }) {
                        scrollProgress = CGFloat(idx) / CGFloat(memories.count - 1)
                    }
                }
                .onPreferenceChange(CenterCardPreferenceKey.self) { cards in
                    guard !cards.isEmpty else { return }
                    let viewportCenter = outerGeo.size.height / 2
                    let closest = cards.min(by: {
                        abs($0.centerY - viewportCenter) < abs($1.centerY - viewportCenter)
                    })
                    if let closest {
                        centerMemoryID = closest.id
                        if memories.count > 1,
                           let idx = memories.firstIndex(where: { $0.id == closest.id }) {
                            scrollProgress = CGFloat(idx) / CGFloat(memories.count - 1)
                        }
                    }
                }
                .onAppear {
                    let target = memories.last?.id
                    centerMemoryID = target
                    scrolledToID = target
                }
                .overlay(alignment: .trailing) {
                    if memories.count > 3 {
                        TimelineScrubberView(
                            memories: memories,
                            scrollProgress: scrollProgress,
                            centerMemoryID: centerMemoryID,
                            onScrub: { memoryID in
                                scrolledToID = memoryID
                            }
                        )
                        .padding(.top, 60)
                        .padding(.bottom, 100)
                        .padding(.trailing, 2)
                    }
                }
                .seasonalTint(for: centerMemoryDate)
        } // GeometryReader
        .fullScreenCover(item: Binding(
            get: { selectedPhotoIndex.map { CinematicPhotoItem(index: $0) } },
            set: { selectedPhotoIndex = $0?.index }
        )) { item in
            PhotoDetailView(memories: photoMemories, initialIndex: item.index)
        }
    }

}

// MARK: - Preference Keys

// MARK: - Extracted Card View (reduces type-checker complexity)

private struct CinematicCardWrapper: View {
    let memory: Memory
    let isHero: Bool
    let availableHeight: CGFloat
    let currentUserID: String?
    let partnerName: String?
    let onTapPhoto: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    // Distance-based scale: 1.0 at center, graduating down to 0.30
    @State private var distanceScale: CGFloat = 0.30

    private var baseHeight: CGFloat {
        CinematicMemoryCard.cardHeight(for: memory.mediaType, in: availableHeight)
    }

    var body: some View {
        CinematicMemoryCard(
            memory: memory,
            isHero: isHero,
            availableHeight: availableHeight,
            currentUserID: currentUserID,
            partnerName: partnerName,
            onTapPhoto: onTapPhoto,
            onEdit: onEdit,
            onDelete: onDelete
        )
        .scaleEffect(distanceScale)
        .frame(height: baseHeight * distanceScale)
        .opacity(0.4 + distanceScale * 0.6)
        .animation(.easeOut(duration: 0.15), value: distanceScale)
        .id(memory.id)
        .background(
            GeometryReader { geo in
                let midY = geo.frame(in: .named("cinematicScroll")).midY
                let viewportCenter = availableHeight / 2
                let distance = abs(midY - viewportCenter) / availableHeight

                Color.clear
                    .preference(
                        key: CenterCardPreferenceKey.self,
                        value: [CenterCardData(id: memory.id, centerY: midY)]
                    )
                    .onAppear { updateScale(distance: distance) }
                    .onChange(of: midY) { _, _ in updateScale(distance: distance) }
            }
        )
    }

    private func updateScale(distance: CGFloat) {
        // distance 0 = center → scale 1.0
        // distance 0.2 = adjacent → scale ~0.55
        // distance 0.4+ = far → scale 0.30
        let s = max(0.30, 1.0 - distance * 2.5)
        if abs(s - distanceScale) > 0.02 {
            distanceScale = s
        }
    }
}

private struct CenterCardData: Equatable {
    let id: String
    let centerY: CGFloat
}

private struct CenterCardPreferenceKey: PreferenceKey {
    static var defaultValue: [CenterCardData] = []
    static func reduce(value: inout [CenterCardData], nextValue: () -> [CenterCardData]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CinematicPhotoItem: Identifiable {
    let index: Int
    var id: Int { index }
}
