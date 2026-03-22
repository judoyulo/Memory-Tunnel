import SwiftUI

/// Loads today's daily card and presents it full-screen.
/// If no card is queued, shows a calm empty state — not an error.
@MainActor
final class DailyCardViewModel: ObservableObject {
    @Published var card: DailyCard?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            card = try await APIClient.shared.dailyCard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markOpened() {
        Task { try? await APIClient.shared.markDailyCardOpened() }
    }
}

struct DailyCardContainerView: View {
    @StateObject private var vm = DailyCardViewModel()

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading {
                ProgressView()
            } else if let card = vm.card {
                DailyCardView(card: card)
                    .transition(.opacity.animation(.mtFade))
            } else {
                DailyCardEmptyView()
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - DailyCardView

struct DailyCardView: View {
    let card: DailyCard
    @State private var showSendFlow = false
    @State private var triggerDot: Bool = false

    var primaryMemory: Memory? { card.memories.first }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Full-bleed photo
                if let memory = primaryMemory {
                    AsyncImage(url: memory.mediaURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.mtSurface
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
                }

                // Gradient overlay — bottom 30%
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: UnitPoint(x: 0.5, y: 0.70),
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Card content
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Trigger dot (accent — emotional peak only for birthday/decay)
                    if card.triggerType != "manual" {
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(Color.mtAccent)
                                .frame(width: 6, height: 6)
                            Text(triggerLabel)
                                .font(.mtCaption)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }

                    // Partner name
                    if let name = card.chapter.partner?.displayName {
                        Text(name)
                            .font(.mtDisplay)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    // Caption
                    if let caption = primaryMemory?.caption {
                        Text(caption)
                            .font(.mtBody)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)
                    }

                    // CTA
                    Button {
                        showSendFlow = true
                    } label: {
                        Text("Send a memory back")
                            .font(.mtLabel)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.mtAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .padding(.top, Spacing.xs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSendFlow) {
            SendFlowView(chapterID: card.chapter.id)
        }
    }

    private var triggerLabel: String {
        switch card.triggerType {
        case "birthday": return "Birthday today"
        case "decay":    return "It's been a while"
        default:         return ""
        }
    }
}

// MARK: - Empty State

struct DailyCardEmptyView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("🌿")
                .font(.system(size: 56))
            Text("All caught up")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
            Text("Come back tomorrow.\nYour next memory is waiting.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }
}
