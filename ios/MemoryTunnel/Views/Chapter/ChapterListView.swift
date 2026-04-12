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
                await BirthdayService.shared.requestAccessIfNeeded(for: active)
                await BirthdayService.shared.checkAndSignal(chapters: active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteChapter(_ chapter: Chapter) async {
        do {
            try await APIClient.shared.deleteChapter(id: chapter.id)
            chapters.removeAll { $0.id == chapter.id }
            NotificationCenter.default.post(name: .chapterDeleted, object: nil, userInfo: ["chapterID": chapter.id])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChapterListView: View {
    @StateObject private var vm = ChapterListViewModel()
    @EnvironmentObject var router: NotificationRouter
    @State private var showInviteFlow = false
    @State private var showFaceScan = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                if vm.isLoading && vm.chapters.isEmpty {
                    ProgressView()
                } else if let err = vm.errorMessage, vm.chapters.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Text(L.couldntLoadMemoryLanes)
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
                    List {
                        ForEach(vm.chapters) { chapter in
                            NavigationLink(value: chapter) {
                                ChapterTileView(chapter: chapter)
                            }
                            .listRowBackground(Color.mtBackground)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let chapter = vm.chapters[index]
                                Task { await vm.deleteChapter(chapter) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(L.memoryLanes)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showInviteFlow = true
                        } label: {
                            Label(L.createMemoryLane, systemImage: "person.badge.plus")
                        }
                        Button {
                            showFaceScan = true
                        } label: {
                            Label(L.findPeopleInPhotos, systemImage: "person.viewfinder")
                        }
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
            .sheet(isPresented: $showFaceScan) {
                FaceScanSheet { showFaceScan = false; Task { await vm.load() } }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onAppear { navigateToPendingChapter() }
            .onChange(of: router.pendingChapterID) { _, _ in navigateToPendingChapter() }
        }
    }

    private func navigateToPendingChapter() {
        guard let chapterID = router.pendingChapterID else { return }

        // Always pop to root first
        navigationPath = NavigationPath()

        Task {
            // Wait for pop animation + tab switch to fully settle
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Ensure chapters are loaded
            if vm.chapters.isEmpty { await vm.load() }

            // Find and navigate
            if let chapter = vm.chapters.first(where: { $0.id == chapterID }) {
                navigationPath.append(chapter)
            } else {
                // Chapter not in list — reload
                await vm.load()
                if let chapter = vm.chapters.first(where: { $0.id == chapterID }) {
                    navigationPath.append(chapter)
                }
            }
            router.pendingChapterID = nil
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
                    Text(L.inviteNotSent)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtTertiary)
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
                    Text(L.share)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mtLabel)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L.shareInviteFor(chapter.name ?? "this chapter"))
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
            Text(L.inviteLinkUnavailable)
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
        guard let last = chapter.lastMemoryAt else { return false }
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
                .foregroundStyle(Color.mtTertiary)
            Text(L.startYourFirst)
                .font(.mtEmptyTitle)
                .foregroundStyle(Color.mtLabel)
            Text(L.sendFirstMemory)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button(action: onInvite) {
                Text(L.inviteSomeone)
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
