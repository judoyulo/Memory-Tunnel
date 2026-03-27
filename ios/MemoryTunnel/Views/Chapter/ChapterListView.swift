import SwiftUI

@MainActor
final class ChapterListViewModel: ObservableObject {
    @Published var chapters: [Chapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chapters = try await APIClient.shared.chapters()
            let active = chapters.filter { $0.status == "active" }
            if !active.isEmpty {
                // Request Contacts access after first active chapter (DESIGN.md permission timing).
                // No-ops if already authorized or denied.
                await BirthdayService.shared.requestAccessIfNeeded(for: active)
                await BirthdayService.shared.checkAndSignal(chapters: active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChapterListView: View {
    @StateObject private var vm = ChapterListViewModel()
    @EnvironmentObject var router: NotificationRouter
    @State private var showInviteFlow = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                if vm.isLoading && vm.chapters.isEmpty {
                    ProgressView()
                } else if let err = vm.errorMessage, vm.chapters.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Text("Couldn't load chapters")
                            .font(.mtTitle)
                            .foregroundStyle(Color.mtLabel)
                        Text(err)
                            .font(.mtCaption)
                            .foregroundStyle(Color.mtSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.xl)
                } else if vm.chapters.isEmpty {
                    ChapterListEmptyView(onInvite: { showInviteFlow = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(vm.chapters) { chapter in
                                if chapter.status == "pending" {
                                    // Pending chapters have no partner yet — not navigable
                                    ChapterTileView(chapter: chapter)
                                } else {
                                    NavigationLink(value: chapter) {
                                        ChapterTileView(chapter: chapter)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInviteFlow = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.mtLabel)
                    }
                }
            }
            .navigationDestination(for: Chapter.self) { chapter in
                ChapterDetailView(chapter: chapter)
            }
            .sheet(isPresented: $showInviteFlow) {
                InviteFlowView()
                    .onDisappear { Task { await vm.load() } }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Chapter Tile

struct ChapterTileView: View {
    let chapter: Chapter
    @State private var showShareSheet = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar pill — 44pt circle, initial letter
            ZStack {
                Capsule()
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

                if chapter.status == "pending" {
                    Text("Invite not sent yet")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.mtSecondary)
                } else if let tag = chapter.lifeChapterTag {
                    Text(tag)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }
            }

            Spacer()

            if chapter.status == "pending" {
                // Share CTA — emotional nudge to complete the chapter
                Button {
                    showShareSheet = true
                } label: {
                    Text("Share")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mtLabel)
                }
                .accessibilityLabel("Share invite link for \(chapter.name ?? "this chapter")")
            } else if isDecayed {
                // Decay indicator (accent dot — emotional peak)
                Circle()
                    .fill(Color.mtAccent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(Spacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.micro))
        .sheet(isPresented: $showShareSheet) {
            // Pending chapters may not have an invitation yet.
            // If we have no URL, show a placeholder message.
            Text("Invite link unavailable.\nTry opening the chapter to generate one.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .padding(Spacing.xl)
                .presentationDetents([.medium])
        }
    }

    private var avatarLetter: String {
        let name = chapter.partner?.displayName ?? chapter.name ?? "?"
        return String(name.prefix(1).uppercased())
    }

    private var isDecayed: Bool {
        guard let last = chapter.lastMemoryAt else { return true }
        return last < Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    }
}

// MARK: - Empty State

struct ChapterListEmptyView: View {
    let onInvite: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "envelope.heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtAccent)
            Text("Start your first chapter")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.mtLabel)
            Text("Send a first memory to someone\nyou want to stay close to.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button(action: onInvite) {
                Text("Invite someone")
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
    }
}
