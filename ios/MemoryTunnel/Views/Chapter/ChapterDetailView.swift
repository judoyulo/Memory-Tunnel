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
            // 15-second timeout to prevent freeze on hung API
            memories = try await withThrowingTaskGroup(of: [Memory].self) { group in
                group.addTask {
                    try await APIClient.shared.memories(chapterID: self.chapterID)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw URLError(.timedOut)
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            print("[ChapterDetail] load error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes signed S3 URLs for memories whose 1hr presigned TTL is approaching.
    /// Called on scenePhase change (.active) so users returning from background see fresh URLs
    /// instead of broken thumbnails.
    func refreshStaleURLsIfNeeded() async {
        guard memories.contains(where: \.needsURLRefresh) else { return }
        await load() // Simpler than per-URL refresh; one extra GET, all URLs renewed
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
            try await APIClient.shared.updateMemory(chapterID: chapterID, memoryID: memory.id, caption: caption)
            await load() // reload for fresh data
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View Mode

enum ChapterViewMode: String {
    case cinematic
    case journal
}

// MARK: - Chapter Detail View (Memory Journal)

struct ChapterDetailView: View {
    let chapter: Chapter
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: ChapterDetailViewModel
    enum ActiveSheet: Identifiable {
        case sendFlow, voiceRecorder, textComposer, shareSheet
        case suggestedPhotos, faceConfirmation, batchReview
        case editMemory(Memory)
        var id: String {
            switch self {
            case .sendFlow: return "send"
            case .voiceRecorder: return "voice"
            case .textComposer: return "text"
            case .shareSheet: return "share"
            case .suggestedPhotos: return "suggested"
            case .faceConfirmation: return "face"
            case .batchReview: return "batch"
            case .editMemory(let m): return "edit-\(m.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var dismissOnThisDay = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewMode: ChapterViewMode
    @State private var batchImages: [(image: UIImage, takenAt: Date?)] = []

    init(chapter: Chapter) {
        self.chapter = chapter
        _vm = StateObject(wrappedValue: ChapterDetailViewModel(chapterID: chapter.id))
        let saved = UserDefaults.standard.string(forKey: "chapterViewMode_\(chapter.id)") ?? ""
        _viewMode = State(initialValue: ChapterViewMode(rawValue: saved) ?? .cinematic)
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

                    // View mode switch: cinematic film strip (default) or journal
                    if viewMode == .cinematic {
                        CinematicTimelineView(
                            memories: vm.memories,
                            currentUserID: currentUserID,
                            partnerName: chapter.partner?.displayName,
                            onDelete: { memory in
                                Task { await vm.deleteMemory(memory) }
                            },
                            onEdit: { memory in
                                activeSheet = .editMemory(memory)
                            }
                        )
                    } else {
                        ConversationTimelineView(
                            memories: vm.memories,
                            currentUserID: currentUserID,
                            partnerName: chapter.partner?.displayName,
                            onDelete: { memory in
                                Task { await vm.deleteMemory(memory) }
                            },
                            onEdit: { memory in
                                activeSheet = .editMemory(memory)
                            }
                        )
                    }
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
                    let newMode: ChapterViewMode = viewMode == .cinematic ? .journal : .cinematic
                    withAnimation(.mtSlide) {
                        viewMode = newMode
                    }
                    UserDefaults.standard.set(newMode.rawValue, forKey: "chapterViewMode_\(chapter.id)")
                } label: {
                    Image(systemName: viewMode == .cinematic ? "list.bullet" : "film")
                        .foregroundStyle(Color.mtLabel)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .shareSheet
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.mtLabel)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 20, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [(image: UIImage, takenAt: Date?)] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { continue }
                    loaded.append((image: image, takenAt: nil))
                }
                selectedPhotos = []
                guard !loaded.isEmpty else { return }
                batchImages = loaded
                activeSheet = .batchReview
            }
        }
        .faceTaggingOverlay(for: chapter)
        .task { await vm.load() }
        .onChange(of: scenePhase) { _, newPhase in
            // Refresh signed S3 URLs when returning to foreground.
            // Photos break after 1hr because presigned URLs expire — proactive refresh prevents broken thumbnails.
            if newPhase == .active {
                Task { await vm.refreshStaleURLsIfNeeded() }
            }
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .sendFlow:
            SendFlowView(chapterID: chapter.id)
                .onDisappear { Task { await vm.load() } }
        case .voiceRecorder:
            VoiceRecorderView(chapterID: chapter.id) { Task { await vm.load() } }
        case .textComposer:
            TextComposerView { text, location, eventDate, tags in
                Task {
                    _ = try? await APIClient.shared.createTextMemory(
                        chapterID: chapter.id, caption: text,
                        locationName: location, eventDate: eventDate,
                        emotionTags: tags.isEmpty ? nil : tags
                    )
                    await vm.load()
                }
            }
        case .editMemory(let memory):
            MemoryEditSheet(
                memory: memory, chapterID: chapter.id,
                onSave: { _ in Task { await vm.load() } },
                onDelete: { Task { await vm.deleteMemory(memory) } }
            )
        case .shareSheet:
            if chapter.partner != nil {
                ShareLink(item: URL(string: "https://app.memorytunnel.com/i/\(chapter.id)")!) {
                    Text(L.shareInviteLink)
                }
            }
        case .suggestedPhotos:
            SuggestedPhotosView(
                chapterID: chapter.id,
                partnerName: chapter.partner?.displayName ?? "them",
                partnerCrop: nil
            ) { selectedAssets in
                activeSheet = nil
                Task {
                    var loaded: [(image: UIImage, takenAt: Date?)] = []
                    for asset in selectedAssets {
                        guard let image = await loadFullImage(for: asset) else { continue }
                        loaded.append((image: image, takenAt: asset.creationDate))
                    }
                    guard !loaded.isEmpty else { return }
                    batchImages = loaded
                    activeSheet = .batchReview
                }
            }
        case .batchReview:
            BatchPhotoReviewView(
                chapterID: chapter.id, initialImages: batchImages
            ) { Task { await vm.load() } }
        case .faceConfirmation:
            ChapterFaceConfirmationView(chapter: chapter, memories: vm.memories)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtAccent)
            Text(L.startThisMemoryLane)
                .font(.mtEmptyTitle)
                .foregroundStyle(Color.mtLabel)
            Text(L.addFirstMemoryBody)
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
                showPhotoPicker = true
            } label: {
                Label(L.photos, systemImage: "photo.on.rectangle")
            }
            Button {
                activeSheet = .suggestedPhotos
            } label: {
                Label(L.findPhotosOf(chapter.partner?.displayName ?? "them"), systemImage: "sparkle.magnifyingglass")
            }
            Button {
                activeSheet = .voiceRecorder
            } label: {
                Label(L.voiceClip, systemImage: "waveform")
            }
            Button {
                activeSheet = .textComposer
            } label: {
                Label(L.writeSomething, systemImage: "text.quote")
            }

            Divider()

            Button {
                activeSheet = .faceConfirmation
            } label: {
                Label(L.setFace(chapter.partner?.displayName ?? "partner"), systemImage: "face.smiling")
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

    // MARK: - Photo Upload Helpers

    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit, options: options
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }

    private func uploadPhotoData(_ image: UIImage, to chapterID: String) async throws -> Memory? {
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else { return nil }
        let presign = try await APIClient.shared.presign(chapterID: chapterID)
        try await APIClient.shared.uploadToS3(data: jpegData, presign: presign)
        let memory = try await APIClient.shared.createMemory(
            chapterID: chapterID,
            s3Key: presign.s3Key,
            caption: nil,
            takenAt: nil,
            visibility: "this_item",
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        Task { await FaceEmbeddingService.shared.processFaces(in: image) }
        return memory
    }

    private func uploadPhoto(_ image: UIImage, to chapterID: String, asset: PHAsset) async throws -> Memory? {
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else { return nil }
        let presign = try await APIClient.shared.presign(chapterID: chapterID)
        try await APIClient.shared.uploadToS3(data: jpegData, presign: presign)
        let memory = try await APIClient.shared.createMemory(
            chapterID: chapterID,
            s3Key: presign.s3Key,
            caption: nil,
            takenAt: asset.creationDate,
            visibility: "this_item",
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        Task { await FaceEmbeddingService.shared.processFaces(in: image) }
        return memory
    }
}

// MemoryCardView removed — replaced by TimelineMemoryCard in ConversationTimelineView
