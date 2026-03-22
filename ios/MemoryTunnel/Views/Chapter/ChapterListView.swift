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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChapterListView: View {
    @StateObject private var vm = ChapterListViewModel()
    @EnvironmentObject var router: NotificationRouter

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                if vm.isLoading && vm.chapters.isEmpty {
                    ProgressView()
                } else if vm.chapters.isEmpty {
                    ChapterListEmptyView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(vm.chapters) { chapter in
                                NavigationLink(value: chapter) {
                                    ChapterTileView(chapter: chapter)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Chapter.self) { chapter in
                ChapterDetailView(chapter: chapter)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Chapter Tile

struct ChapterTileView: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar pill — 24pt, top-left
            if let name = chapter.partner?.displayName {
                ZStack {
                    Capsule()
                        .fill(Color.mtSurface)
                        .frame(width: 44, height: 44)
                    Text(name.prefix(1).uppercased())
                        .font(.mtLabel)
                        .foregroundStyle(Color.mtLabel)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.partner?.displayName ?? "Someone")
                    .font(.mtLabel)
                    .foregroundStyle(Color.mtLabel)
                if let tag = chapter.lifeChapterTag {
                    Text(tag)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }
            }

            Spacer()

            // Decay indicator (accent dot — emotional peak)
            if isDecayed {
                Circle()
                    .fill(Color.mtAccent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(Spacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.micro))
    }

    private var isDecayed: Bool {
        guard let last = chapter.lastMemoryAt else { return true }
        return last < Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    }
}

// MARK: - Empty State

struct ChapterListEmptyView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("💌")
                .font(.system(size: 56))
            Text("No chapters yet")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
            Text("Send a memory to start\na chapter with someone.")
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
