import SwiftUI

@MainActor
final class ChapterDetailViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var visibility: String = "this_item"

    let chapterID: String

    init(chapterID: String) {
        self.chapterID = chapterID
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            memories = try await APIClient.shared.memories(chapterID: chapterID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateVisibility(_ vis: String) async {
        do {
            try await APIClient.shared.updateVisibility(chapterID: chapterID, visibility: vis)
            visibility = vis
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMemory(_ memory: Memory) async {
        do {
            try await APIClient.shared.deleteMemory(chapterID: chapterID, memoryID: memory.id)
            memories.removeAll { $0.id == memory.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChapterDetailView: View {
    let chapter: Chapter
    @StateObject private var vm: ChapterDetailViewModel
    @State private var showSendFlow = false
    @State private var showVisibilityPicker = false
    @EnvironmentObject var appState: AppState

    init(chapter: Chapter) {
        self.chapter = chapter
        _vm = StateObject(wrappedValue: ChapterDetailViewModel(chapterID: chapter.id))
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading && vm.memories.isEmpty {
                ProgressView()
            } else if vm.memories.isEmpty {
                VStack(spacing: Spacing.lg) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.mtAccent)
                    Text("No memories yet")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.mtLabel)
                    Text("Send the first memory\nto start this chapter.")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Button("Send a memory") { showSendFlow = true }
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .padding(.horizontal, Spacing.xl)
                    Spacer()
                    Spacer()
                }
                .padding(Spacing.xl)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(vm.memories) { memory in
                            MemoryThumbnailView(memory: memory)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .navigationTitle(chapter.partner?.displayName ?? "Chapter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Send a memory") { showSendFlow = true }
                    Divider()
                    Button("Show all my memories") { Task { await vm.updateVisibility("all") } }
                    Button("Only show sent memories") { Task { await vm.updateVisibility("this_item") } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.mtLabel)
                }
            }
        }
        .sheet(isPresented: $showSendFlow) {
            SendFlowView(chapterID: chapter.id)
        }
        .task { await vm.load() }
    }
}

// MARK: - Memory Thumbnail

struct MemoryThumbnailView: View {
    let memory: Memory

    var body: some View {
        AsyncImage(url: memory.mediaURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color.mtSurface
        }
        .clipped()
    }
}
