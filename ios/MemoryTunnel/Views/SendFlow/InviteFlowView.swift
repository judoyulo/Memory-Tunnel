import SwiftUI
import PhotosUI

// MARK: - ViewModel

@MainActor
final class InviteFlowViewModel: ObservableObject {

    enum Step { case name, pickPhoto, addCaption, sending, done, error(String) }

    @Published var step: Step = .name
    @Published var personName: String

    init(initialName: String? = nil) {
        self.personName = initialName ?? ""
    }
    @Published var selectedItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var detectedFaces: [CGRect] = []
    @Published var caption: String = ""

    private(set) var createdInvitation: Invitation?
    private var createdChapterID: String?

    // MARK: - Actions

    func proceedToPhoto() {
        step = .pickPhoto
    }

    func loadSelectedImage() async {
        guard let item = selectedItem else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            step = .error("Couldn't load that photo. Please try another.")
            return
        }

        selectedImage = image
        step = .addCaption

        detectedFaces = await FaceDetectionService.detectFaces(in: image)
    }

    func send() async {
        guard let image = selectedImage else { return }
        // Prevent double-tap: only proceed from caption step
        guard case .addCaption = step else { return }
        step = .sending

        do {
            // 1. Create chapter (idempotent — reuse if already created on a prior attempt)
            let chapterID: String
            if let existingID = createdChapterID {
                chapterID = existingID
            } else {
                let chapter = try await APIClient.shared.createChapter(
                    name: personName.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                          : personName.trimmingCharacters(in: .whitespaces)
                )
                createdChapterID = chapter.id
                chapterID = chapter.id
            }

            // 2. Compress image
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                throw APIError.httpError(0, "Image compression failed")
            }

            // 3. Get presigned S3 URL
            let presign = try await APIClient.shared.presign(chapterID: chapterID)

            // 4. Upload directly to S3
            try await APIClient.shared.uploadToS3(data: data, presign: presign)

            // 5. Create memory record
            let memory = try await APIClient.shared.createMemory(
                chapterID:  chapterID,
                s3Key:      presign.s3Key,
                caption:    caption.isEmpty ? nil : caption,
                takenAt:    nil,
                visibility: "this_item"
            )

            // 6. Create invitation link (non-fatal — chapter + memory already exist)
            createdInvitation = try? await APIClient.shared.createInvitation(
                chapterID: chapterID,
                memoryID:  memory.id
            )

            step = .done

            // Fire-and-forget: index faces in the uploaded photo for the tagging prompt queue.
            Task { await FaceEmbeddingService.shared.processFaces(in: image) }
        } catch {
            step = .error(error.localizedDescription)
        }
    }
}

// MARK: - View

struct InviteFlowView: View {
    @StateObject private var vm: InviteFlowViewModel
    @Environment(\.dismiss) private var dismiss

    init(initialName: String? = nil) {
        _vm = StateObject(wrappedValue: InviteFlowViewModel(initialName: initialName))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                switch vm.step {
                case .name:
                    InviteNameStep(vm: vm)
                case .pickPhoto:
                    InvitePhotoStep(vm: vm)
                case .addCaption:
                    InviteCaptionStep(vm: vm)
                case .sending:
                    InviteSendingStep()
                case .done:
                    InviteDoneStep(vm: vm, dismiss: { dismiss() })
                case .error(let msg):
                    InviteErrorStep(message: msg) { vm.step = .addCaption }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .done = vm.step { EmptyView() }
                    else {
                        Button(L.cancel) { dismiss() }
                            .foregroundStyle(Color.mtSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Step: Name

private struct InviteNameStep: View {
    @ObservedObject var vm: InviteFlowViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text(L.whoStayClose)
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)

                Text(L.theirNameHelps)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            TextField(L.theirName, text: $vm.personName)
                .font(.mtBody)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit { vm.proceedToPhoto() }

            Button {
                vm.proceedToPhoto()
            } label: {
                Text(L.chooseAPhoto)
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Pick Photo

private struct InvitePhotoStep: View {
    @ObservedObject var vm: InviteFlowViewModel

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text(L.sendThemFirst)
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)

                Text(L.photoThatMakesYouThink)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $vm.selectedItem, matching: .images) {
                Label(L.openPhotos, systemImage: "photo.on.rectangle")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .onChange(of: vm.selectedItem) { _, _ in
                Task { await vm.loadSelectedImage() }
            }

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Caption

private struct InviteCaptionStep: View {
    @ObservedObject var vm: InviteFlowViewModel
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let image = vm.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()
                    .overlay(FaceOverlayView(faces: vm.detectedFaces))
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                TextField(L.captionOptional, text: $vm.caption, axis: .vertical)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .focused($captionFocused)
                    .lineLimit(3)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                Button {
                    captionFocused = false
                    Task { await vm.send() }
                } label: {
                    Text(L.sendAndInvite)
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
            }
            .padding(Spacing.md)

            Spacer()
        }
    }
}

// MARK: - Step: Sending

private struct InviteSendingStep: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
            Text(L.creatingYourMemoryLane)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }
}

// MARK: - Step: Done ✓

private struct InviteDoneStep: View {
    let vm: InviteFlowViewModel
    let dismiss: () -> Void
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Accent checkmark — emotional peak (✓ sent)
            ZStack {
                Circle()
                    .fill(Color.mtAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.mtAccent)
            }

            Text(L.memorySent)
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text(L.shareLinkToJoin)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if let url = vm.createdInvitation?.shareURL {
                Button {
                    showShareSheet = true
                } label: {
                    Label(L.shareInviteLink, systemImage: "square.and.arrow.up")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [url])
                }
            }

            Button(L.done) { dismiss() }
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)

            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Error

private struct InviteErrorStep: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text(L.somethingWentWrong)
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
            Text(message)
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
            Button(L.tryAgain, action: retry)
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
        .padding(Spacing.xl)
    }
}
