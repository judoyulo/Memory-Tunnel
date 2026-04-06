import SwiftUI

// MARK: - Photo Detail View
//
// Full-bleed photo viewer with daily card gradient pattern.
// Swipe left/right between chapter photos via TabView.
// Metadata overlay: location + "N years ago".

struct PhotoDetailView: View {
    let memories: [Memory]
    let initialIndex: Int
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(memories: [Memory], initialIndex: Int) {
        self.memories = memories
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentMemory: Memory? {
        guard currentIndex >= 0, currentIndex < memories.count else { return nil }
        return memories[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(memories.enumerated()), id: \.element.id) { index, memory in
                    ZoomablePhotoContent(url: memory.mediaURL)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: memories.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            // Gradient overlay (bottom 30%, matches daily card pattern)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: UnitPoint(x: 0.5, y: 0.0),
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Metadata overlay
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Spacing.md)
                    .padding(.top, 8)
                }

                Spacer()

                if let memory = currentMemory {
                    VStack(alignment: .leading, spacing: 6) {
                        if let loc = memory.locationName {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12))
                                Text(loc)
                                    .font(.system(size: 15))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                        }

                        Text(timeAgoText(for: memory))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))

                        if let caption = memory.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.mtBody)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
        }
    }

    private func timeAgoText(for memory: Memory) -> String {
        let date = memory.takenAt ?? memory.createdAt
        let components = Calendar.current.dateComponents([.year, .month], from: date, to: Date())
        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        return "Recently"
    }
}
