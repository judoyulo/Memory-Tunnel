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
            // Don't show error for decoding failures or network issues.
            // The Today tab has useful fallback states (chapter previews, warm onramp).
            // Only surface errors that indicate a real auth problem.
            print("[DailyCard] load failed: \(error)")
            card = nil
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
                TodayWarmOnrampView()
            } else {
                TodayChapterPreviewsView()
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - State 1: No Chapters — Warm Onramp

struct TodayWarmOnrampView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInviteFlow = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.currentUser?.displayName ?? ""
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Good morning"
        case 12..<17: prefix = "Good afternoon"
        default:      prefix = "Good evening"
        }
        return name.isEmpty ? prefix : "\(prefix), \(name)"
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Text(greeting)
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)
                .multilineTextAlignment(.center)

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtAccent)

            Text("Your daily memories start\nwhen you share your first photo.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showInviteFlow = true
            } label: {
                Text("Start a chapter")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
        .sheet(isPresented: $showInviteFlow) {
            InviteFlowView()
        }
    }
}

// MARK: - State 2: Has Chapters, No Card — Chapter Previews + Quick Send

struct TodayChapterPreviewsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInviteFlow = false
    @State private var sendChapterID: String?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.currentUser?.displayName ?? ""
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Good morning"
        case 12..<17: prefix = "Good afternoon"
        default:      prefix = "Good evening"
        }
        return name.isEmpty ? prefix : "\(prefix), \(name)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(greeting)
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                    .padding(.top, Spacing.xl)

                Text("No card today. Send a memory to someone you miss.")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)

                ForEach(appState.chapters) { chapter in
                    ChapterPreviewCard(
                        chapter: chapter,
                        onSend: { sendChapterID = chapter.id }
                    )
                }

                // Add another chapter
                Button {
                    showInviteFlow = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Start another chapter")
                            .font(.mtButton)
                    }
                    .foregroundStyle(Color.mtLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .stroke(Color.mtLabel, lineWidth: 1.5)
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 80) // Extra padding to clear the tab bar
        }
        .sheet(isPresented: $showInviteFlow) {
            InviteFlowView()
        }
        .sheet(item: Binding(
            get: { sendChapterID.map { SendChapterID(id: $0) } },
            set: { sendChapterID = $0?.id }
        )) { item in
            SendFlowView(chapterID: item.id)
        }
    }
}

/// Identifiable wrapper for sheet binding
private struct SendChapterID: Identifiable {
    let id: String
}

// MARK: - Chapter Preview Card with Health Dot

struct ChapterPreviewCard: View {
    let chapter: Chapter
    let onSend: () -> Void

    private var healthColor: Color {
        guard let last = chapter.lastMemoryAt else { return Color.mtAccent } // never exchanged = cold
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if daysSince < 30 { return Color(red: 0.298, green: 0.686, blue: 0.475) } // #4CAF79 active
        if daysSince < 90 { return Color.mtTertiary } // quiet
        return Color.mtAccent // cold (decay threshold)
    }

    private var healthLabel: String {
        guard let last = chapter.lastMemoryAt else { return "No memories yet" }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if daysSince == 0 { return "Active today" }
        if daysSince == 1 { return "Last memory yesterday" }
        return "Last memory \(daysSince) days ago"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Health dot
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)

            // Avatar
            ZStack {
                Circle()
                    .fill(Color.mtSurface)
                    .frame(width: 44, height: 44)
                Text(avatarLetter)
                    .font(.mtLabel)
                    .foregroundStyle(Color.mtLabel)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.partner?.displayName ?? chapter.name ?? "Pending")
                    .font(.mtLabel)
                    .foregroundStyle(Color.mtLabel)
                Text(healthLabel)
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
            }

            Spacer()

            Button(action: onSend) {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mtBackground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.mtLabel)
                    .clipShape(Capsule())
            }
        }
        .padding(Spacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private var avatarLetter: String {
        let name = chapter.partner?.displayName ?? chapter.name ?? "?"
        return String(name.prefix(1).uppercased())
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
                    // Trigger dot (accent — emotional peak: welcome/birthday/decay)
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
        case "welcome":  return "First memory sent"
        case "birthday": return "Birthday today"
        case "decay":    return "It's been a while"
        default:         return ""
        }
    }

}

// DailyCardEmptyView removed — replaced by TodayChapterPreviewsView (State 2)
