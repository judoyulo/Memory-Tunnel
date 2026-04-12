import SwiftUI

/// Screen 6: Face Bubbles — the "people map" from your photo library.
/// Faces appear progressively as they're discovered during scanning.
/// Bubble size is proportional to how many photos contain that face.
/// Tap a bubble to create a chapter with that person.
struct FaceBubblesView: View {
    @Binding var suggestions: [FaceSuggestion]
    let isScanning: Bool
    let onSelectFace: (Int) -> Void       // index into suggestions
    let onManualCreate: () -> Void
    let onSkip: () -> Void
    let completedFaces: Set<UUID>          // dimmed faces (batch creation)

    @State private var bubblePositions: [PositionedBubble] = []
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: Spacing.xs) {
                    Text(isScanning ? L.findingPeople : L.peopleFromPhotos)
                        .font(.mtEmptyTitle)
                        .foregroundStyle(Color.mtLabel)

                    if isScanning {
                        ProgressView()
                            .padding(.top, Spacing.xs)
                    }
                }
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.md)

                // Bubble area
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(bubblePositions.enumerated()), id: \.element.id) { offset, bubble in
                            if bubble.suggestionIndex < suggestions.count,
                               bubble.suggestionIndex >= 0 {
                                let suggestion = suggestions[bubble.suggestionIndex]
                                let isCompleted = completedFaces.contains(suggestion.id)

                                Button {
                                    if !isCompleted {
                                        onSelectFace(bubble.suggestionIndex)
                                    }
                                } label: {
                                    ZStack {
                                        Image(uiImage: suggestion.sampleCrop)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: bubble.radius * 2, height: bubble.radius * 2)
                                            .clipShape(Circle())
                                            .opacity(isCompleted ? 0.3 : 1)

                                        if isCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: bubble.radius * 0.6))
                                                .foregroundStyle(Color.mtAccent)
                                        }
                                    }
                                }
                                .position(bubble.center)
                                .scaleEffect(appeared ? 1 : 0.01)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.7)
                                        .delay(Double(offset) * 0.06),
                                    value: appeared
                                )
                                .accessibilityLabel(isCompleted
                                    ? L.chapterCreated()
                                    : "Person appearing in \(suggestion.count) photos"
                                )
                            }
                        }
                    }
                    .onChange(of: suggestions.count) { _, _ in
                        recomputeLayout(size: geo.size)
                    }
                    .onAppear {
                        recomputeLayout(size: geo.size)
                        withAnimation { appeared = true }
                    }
                }

                // Bottom actions
                VStack(spacing: Spacing.md) {
                    Button(L.choosePhotosManually) {
                        onManualCreate()
                    }
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .stroke(Color.mtLabel, lineWidth: 1.5)
                    )

                    Button(L.skip) {
                        onSkip()
                    }
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
    }

    private func recomputeLayout(size: CGSize) {
        // Usable area for bubbles (subtract header and bottom buttons)
        let bubbleArea = CGSize(
            width: size.width,
            height: max(200, size.height)
        )

        let counts = suggestions.enumerated().map { (index, s) in
            (index: index, id: s.id, count: s.count)
        }

        bubblePositions = FaceBubbleLayout.layout(
            counts: counts,
            containerSize: bubbleArea
        )
    }
}
