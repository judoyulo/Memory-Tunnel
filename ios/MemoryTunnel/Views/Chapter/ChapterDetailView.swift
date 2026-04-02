import SwiftUI
import PhotosUI

@MainActor
final class ChapterDetailViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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
            print("[ChapterDetail] load error: \(error)")
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

    func addTextMemory(caption: String) async {
        do {
            let memory = try await APIClient.shared.createTextMemory(chapterID: chapterID, caption: caption)
            memories.append(memory) // ASC order: newest at bottom
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCaption(memory: Memory, caption: String) async {
        do {
            let updated = try await APIClient.shared.updateMemory(chapterID: chapterID, memoryID: memory.id, caption: caption)
            if let index = memories.firstIndex(where: { $0.id == updated.id }) {
                memories[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Chapter Detail View (Memory Journal)

struct ChapterDetailView: View {
    let chapter: Chapter
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: ChapterDetailViewModel
    @State private var showSendFlow = false
    @State private var showVoiceRecorder = false
    @State private var showTextComposer = false
    @State private var showShareSheet = false
    @State private var dismissOnThisDay = false
    @State private var editingMemory: Memory?

    init(chapter: Chapter) {
        self.chapter = chapter
        _vm = StateObject(wrappedValue: ChapterDetailViewModel(chapterID: chapter.id))
    }

    private var currentUserID: String? {
        appState.currentUser?.id
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading && vm.memories.isEmpty {
                ProgressView()
            } else if vm.memories.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // On This Day card
                    if !dismissOnThisDay,
                       let match = OnThisDayCard.findMatch(in: vm.memories) {
                        OnThisDayCard(memory: match, onDismiss: { dismissOnThisDay = true })
                            .padding(.top, Spacing.sm)
                    }

                    // Journal timeline (metadata-first, single column)
                    ConversationTimelineView(
                        memories: vm.memories,
                        currentUserID: currentUserID,
                        partnerName: chapter.partner?.displayName,
                        onDelete: { memory in
                            Task { await vm.deleteMemory(memory) }
                        },
                        onEdit: { memory in
                            editingMemory = memory
                        }
                    )
                }
            }

            // Floating '+' button
            addButton
        }
        .navigationTitle(chapter.name ?? chapter.partner?.displayName ?? "Chapter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if chapter.partner?.displayName != nil {
                    Text(relationshipAge)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mtTertiary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.mtLabel)
                }
            }
        }
        .sheet(isPresented: $showSendFlow) {
            SendFlowView(chapterID: chapter.id)
                .onDisappear { Task { await vm.load() } }
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView(chapterID: chapter.id) {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showTextComposer) {
            TextComposerView { text, location, eventDate, tags in
                Task {
                    _ = try? await APIClient.shared.createTextMemory(
                        chapterID: chapter.id,
                        caption: text,
                        locationName: location,
                        eventDate: eventDate,
                        emotionTags: tags.isEmpty ? nil : tags
                    )
                    await vm.load()
                }
            }
        }
        .sheet(item: $editingMemory) { memory in
            MemoryEditSheet(
                memory: memory,
                chapterID: chapter.id,
                onSave: { updated in
                    if let idx = vm.memories.firstIndex(where: { $0.id == updated.id }) {
                        vm.memories[idx] = updated
                    }
                },
                onDelete: {
                    Task { await vm.deleteMemory(memory) }
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if chapter.partner != nil {
                ShareLink(item: URL(string: "https://app.memorytunnel.com/i/\(chapter.id)")!) {
                    Text("Share invite link")
                }
            }
        }
        .faceTaggingOverlay(for: chapter)
        .task { await vm.load() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtAccent)
            Text("Start this chapter")
                .font(.mtEmptyTitle)
                .foregroundStyle(Color.mtLabel)
            Text("Add your first memory.\nPhotos, voice clips, or just a few words.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }

    // MARK: - Floating Add Button

    private var addButton: some View {
        Menu {
            Button {
                showSendFlow = true
            } label: {
                Label("Photo", systemImage: "photo")
            }
            Button {
                showVoiceRecorder = true
            } label: {
                Label("Voice clip", systemImage: "waveform")
            }
            Button {
                showTextComposer = true
            } label: {
                Label("Write something", systemImage: "text.quote")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.mtBackground)
                .frame(width: 56, height: 56)
                .background(Color.mtLabel)
                .clipShape(Circle())
        }
        .padding(.trailing, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Relationship Age

    private var relationshipAge: String {
        // Use chapter creation date as relationship start
        // (chapters don't have createdAt exposed, so use first memory or lastMemoryAt)
        guard let firstMemoryDate = vm.memories.first?.createdAt ?? chapter.lastMemoryAt else {
            return ""
        }
        let components = Calendar.current.dateComponents([.year, .month], from: firstMemoryDate, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 && months > 0 {
            return "\(years)y \(months)m"
        } else if years > 0 {
            return "\(years) year\(years == 1 ? "" : "s")"
        } else if months > 0 {
            return "\(months) month\(months == 1 ? "" : "s")"
        }
        return "Just started"
    }
}

// MemoryCardView removed — replaced by TimelineMemoryCard in ConversationTimelineView
