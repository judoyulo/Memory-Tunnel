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
            memories.insert(memory, at: 0)
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

// MARK: - Chapter Detail View (Timeline Feed)

struct ChapterDetailView: View {
    let chapter: Chapter
    @StateObject private var vm: ChapterDetailViewModel
    @State private var showAddMenu = false
    @State private var showSendFlow = false
    @State private var showVoiceFlow = false
    @State private var showTextEntry = false
    @State private var newTextContent = ""
    @State private var showShareSheet = false

    init(chapter: Chapter) {
        self.chapter = chapter
        _vm = StateObject(wrappedValue: ChapterDetailViewModel(chapterID: chapter.id))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading && vm.memories.isEmpty {
                ProgressView()
            } else if vm.memories.isEmpty {
                emptyState
            } else {
                timeline
            }

            // Floating '+' button
            addButton
        }
        .navigationTitle(chapter.name ?? chapter.partner?.displayName ?? "Chapter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .sheet(isPresented: $showVoiceFlow) {
            VoiceFlowView(chapterID: chapter.id)
                .onDisappear { Task { await vm.load() } }
        }
        .sheet(isPresented: $showTextEntry) {
            textEntrySheet
        }
        .sheet(isPresented: $showShareSheet) {
            if let invitation = chapter.partner {
                // Share the chapter invitation link
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

    // MARK: - Timeline Feed

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(vm.memories) { memory in
                    MemoryCardView(memory: memory, onDelete: {
                        Task { await vm.deleteMemory(memory) }
                    })
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, 80) // space for floating button
        }
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
                showVoiceFlow = true
            } label: {
                Label("Voice clip", systemImage: "waveform")
            }
            Button {
                showTextEntry = true
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
                // No shadow — DESIGN.md: "Decoration level: None"
        }
        .padding(.trailing, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Text Entry Sheet

    private var textEntrySheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                TextField("Write a memory, thought, or note...", text: $newTextContent, axis: .vertical)
                    .font(.mtBody)
                    .lineLimit(5...10)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))

                Spacer()
            }
            .padding(Spacing.xl)
            .background(Color.mtBackground)
            .navigationTitle("Write something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        newTextContent = ""
                        showTextEntry = false
                    }
                    .foregroundStyle(Color.mtSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let text = newTextContent
                        newTextContent = ""
                        showTextEntry = false
                        Task { await vm.addTextMemory(caption: text) }
                    }
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .disabled(newTextContent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Memory Card (Timeline Item)

struct MemoryCardView: View {
    let memory: Memory
    let onDelete: () -> Void
    @State private var showPlayer = false
    @State private var localAudioURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date + location header
            HStack(spacing: Spacing.xs) {
                if let date = memory.takenAt ?? Optional(memory.createdAt) {
                    Text(date, style: .date)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtTertiary)
                }
                if let loc = memory.locationName {
                    Text("·")
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtTertiary)
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mtTertiary)
                    Text(loc)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            // Content based on type
            switch memory.mediaType {
            case "photo":
                photoContent
            case "voice":
                voiceContent
            case "text":
                textContent
            case "location_checkin":
                locationContent
            default:
                textContent
            }

            // Caption (if present and not a text-only memory)
            if memory.mediaType != "text", let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.sm)
            }
        }
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Photo Card

    @ViewBuilder
    private var photoContent: some View {
        AsyncImage(url: memory.mediaURL ?? URL(string: "about:blank")) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color.mtSurface
                .frame(height: 240)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .clipped()
    }

    // MARK: - Voice Card

    @ViewBuilder
    private var voiceContent: some View {
        VStack(spacing: Spacing.sm) {
            if let localURL = localAudioURL {
                VoicePlayerView(url: localURL)
            } else {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.mtSecondary)
                    Text("Voice clip")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                    Button("Play") {
                        Task { await downloadAudio() }
                    }
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtLabel)
                }
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - Text Card

    @ViewBuilder
    private var textContent: some View {
        Text(memory.caption ?? "")
            .font(.mtBody)
            .foregroundStyle(Color.mtLabel)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Location Check-in Card

    @ViewBuilder
    private var locationContent: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.mtSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.locationName ?? "Somewhere")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                if let caption = memory.caption {
                    Text(caption)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }
            }
            Spacer()
        }
        .padding(Spacing.md)
    }

    private func downloadAudio() async {
        guard localAudioURL == nil else { return }
        guard let url = memory.mediaURL,
              let data = try? await URLSession.shared.data(from: url).0 else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(memory.id)
            .appendingPathExtension("m4a")
        try? data.write(to: tmp)
        await MainActor.run { localAudioURL = tmp }
    }
}
