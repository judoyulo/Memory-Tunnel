import SwiftUI
import WidgetKit

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
            updateWidgetData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markOpened() {
        Task { try? await APIClient.shared.markDailyCardOpened() }
    }

    /// Write daily card data to App Group shared UserDefaults so the widget can display it.
    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.memorytunnel.app") else { return }

        if let card {
            defaults.set(card.chapter.partner?.displayName, forKey: "widget.partnerName")
            defaults.set(card.memories.first?.mediaURL?.absoluteString, forKey: "widget.imageURL")
            defaults.set(card.chapter.id, forKey: "widget.chapterID")
        } else {
            // No card today — clear widget data so it shows the calm empty state
            defaults.removeObject(forKey: "widget.partnerName")
            defaults.removeObject(forKey: "widget.imageURL")
            defaults.removeObject(forKey: "widget.chapterID")
        }

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct DailyCardContainerView: View {
    @StateObject private var vm = DailyCardViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading {
                ProgressView()
            } else if let err = vm.errorMessage {
                VStack(spacing: Spacing.md) {
                    Text("Something went wrong")
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                    Text(err)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.xl)
            } else if let card = vm.card {
                DailyCardView(card: card)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97))
                                .animation(.mtReveal),
                            removal: .opacity.animation(.mtFade)
                        )
                    )
            } else if !appState.hasChapters {
                // New user with no chapters: guide them to create one
                TodayNewUserView()
            } else {
                DailyCardEmptyView()
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Smart Today: New User State

struct TodayNewUserView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtTertiary)
            Text("Your daily memories\nwill appear here")
                .font(.mtEmptyTitle)
                .foregroundStyle(Color.mtLabel)
                .multilineTextAlignment(.center)
            Text("Start by creating a chapter with\nsomeone you want to stay close to.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Text("Tap the Chapters tab to begin.")
                .font(.mtCaption)
                .foregroundStyle(Color.mtTertiary)
            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
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
                            .font(.mtButton)
                            .foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.mtLabel)
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
            Image(systemName: "leaf.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtTertiary)
            Text("All caught up")
                .font(.mtEmptyTitle)
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
