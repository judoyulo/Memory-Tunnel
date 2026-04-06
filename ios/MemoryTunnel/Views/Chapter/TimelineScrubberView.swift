import SwiftUI

struct TimelineScrubberView: View {
    let memories: [Memory]
    let scrollProgress: CGFloat
    let centerMemoryID: String?
    var onScrub: ((String) -> Void)?

    @State private var isDragging = false
    @State private var holdTimerStarted = false
    @GestureState private var dragActive = false

    private var currentYear: String {
        guard let id = centerMemoryID,
              let m = memories.first(where: { $0.id == id }) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        return fmt.string(from: m.displayDate)
    }

    /// Unique years with first memory ID for each
    private var years: [(year: String, memoryID: String)] {
        guard memories.count > 1 else { return [] }
        var result: [(String, String)] = []
        var lastYear = ""
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        for m in memories {
            let y = fmt.string(from: m.displayDate)
            if y != lastYear { result.append((y, m.id)); lastYear = y }
        }
        return result
    }

    private var currentYearIndex: Int {
        years.firstIndex(where: { $0.year == currentYear }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height
            let thumbH: CGFloat = isDragging ? 56 : 36
            let thumbW: CGFloat = isDragging ? 12 : 6
            let thumbY = scrollProgress * (trackH - thumbH)

            HStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    Spacer()

                    // Year display — cinematic mini-scroll at mid-right
                    VStack(spacing: 2) {
                        ForEach(Array(years.enumerated()), id: \.offset) { i, entry in
                            let offset = i - currentYearIndex
                            if abs(offset) <= 2 {
                                Button { onScrub?(entry.memoryID) } label: {
                                    Text(entry.year)
                                        .font(.system(
                                            size: offset == 0 ? 13 : (abs(offset) == 1 ? 10 : 8),
                                            weight: offset == 0 ? .bold : .regular
                                        ))
                                        .foregroundStyle(
                                            offset == 0 ? Color.mtLabel : Color.mtTertiary.opacity(abs(offset) == 1 ? 0.6 : 0.3)
                                        )
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: currentYear)

                    Spacer()
                }

                // Track + thumb
                ZStack(alignment: .top) {
                    // Track line
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.mtLabel.opacity(0.06))
                        .frame(width: 3, height: trackH)

                    // Thumb
                    RoundedRectangle(cornerRadius: thumbW / 2)
                        .fill(Color.mtLabel.opacity(isDragging ? 0.5 : 0.2))
                        .frame(width: thumbW, height: thumbH)
                        .offset(y: thumbY)
                        .animation(.easeOut(duration: 0.08), value: scrollProgress)
                        .animation(.spring(response: 0.2), value: isDragging)
                }
                .frame(width: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragActive) { _, state, _ in state = true }
                        .onChanged { value in
                            if !isDragging && !holdTimerStarted {
                                // Start hold timer — enlarge after 0.3s
                                holdTimerStarted = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    guard holdTimerStarted else { return }
                                    isDragging = true
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }
                            // Always scroll immediately (even before enlarge)
                            let progress = min(max(value.location.y / trackH, 0), 1)
                            let idx = min(max(Int(progress * CGFloat(memories.count - 1)), 0), memories.count - 1)
                            onScrub?(memories[idx].id)
                        }
                        .onEnded { _ in
                            isDragging = false
                            holdTimerStarted = false
                        }
                )
            }
        }
        .frame(width: 52)
        .onChange(of: dragActive) { _, active in
            if !active { isDragging = false; holdTimerStarted = false }
        }
    }
}
