import SwiftUI
import PhotosUI

// MARK: - ViewModel

@MainActor
final class SendFlowViewModel: ObservableObject {

    enum Step { case pickPhoto, addCaption, sending, sent, error(String) }

    @Published var step: Step = .pickPhoto
    @Published var selectedItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var detectedFaces: [CGRect] = []
    @Published var caption: String = ""
    @Published var visibility: String = "this_item"   // default: explicitly shared

    let chapterID: String
    var createdInvitation: Invitation?

    init(chapterID: String) { self.chapterID = chapterID }

    // MARK: - Actions

    func loadSelectedImage() async {
        guard let item = selectedItem,
              let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        selectedImage = image
        step = .addCaption

        // On-device face detection (async, non-blocking)
        detectedFaces = await FaceDetectionService.detectFaces(in: image)
    }

    func send() async {
        guard let image = selectedImage else { return }
        step = .sending

        do {
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                throw APIError.httpError(0, "Image compression failed")
            }

            // 1. Get presigned S3 URL
            let presign = try await APIClient.shared.presign(chapterID: chapterID)

            // 2. Upload directly to S3 (no server traffic)
            try await APIClient.shared.uploadToS3(data: data, presign: presign)

            // 3. Create the Memory record
            let memory = try await APIClient.shared.createMemory(
                chapterID:  chapterID,
                s3Key:      presign.s3Key,
                caption:    caption.isEmpty ? nil : caption,
                takenAt:    nil,
                visibility: visibility
            )

            // 4. Create invitation (generates share URL for Branch.io)
            createdInvitation = try? await APIClient.shared.createInvitation(
                chapterID: chapterID,
                memoryID:  memory.id
            )

            step = .sent

            // Fire-and-forget: index faces in the uploaded photo for the tagging prompt queue.
            Task { await FaceIndexService.shared.processFaces(in: image) }
        } catch {
            step = .error(error.localizedDescription)
        }
    }
}

// MARK: - View

struct SendFlowView: View {
    let chapterID: String
    @StateObject private var vm: SendFlowViewModel
    @Environment(\.dismiss) private var dismiss

    init(chapterID: String) {
        self.chapterID = chapterID
        _vm = StateObject(wrappedValue: SendFlowViewModel(chapterID: chapterID))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                switch vm.step {
                case .pickPhoto:
                    PhotoPickerStep(vm: vm)
                case .addCaption:
                    CaptionStep(vm: vm)
                case .sending:
                    SendingStep()
                case .sent:
                    SentStep(vm: vm, dismiss: { dismiss() })
                case .error(let msg):
                    ErrorStep(message: msg, retry: { vm.step = .addCaption })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .sent = vm.step { EmptyView() }
                    else {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.mtSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Step: Pick Photo

struct PhotoPickerStep: View {
    @ObservedObject var vm: SendFlowViewModel

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Text("Choose a photo")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            PhotosPicker(selection: $vm.selectedItem, matching: .images) {
                Label("Open Photos", systemImage: "photo.on.rectangle")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .padding(.horizontal, Spacing.xl)
            .onChange(of: vm.selectedItem) { _, _ in
                Task { await vm.loadSelectedImage() }
            }
            Spacer()
        }
    }
}

// MARK: - Step: Add Caption

struct CaptionStep: View {
    @ObservedObject var vm: SendFlowViewModel
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Preview
            if let image = vm.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()
                    .overlay(FaceOverlayView(faces: vm.detectedFaces))
            }

            // Caption input
            VStack(alignment: .leading, spacing: Spacing.md) {
                TextField("Add a caption… (optional)", text: $vm.caption, axis: .vertical)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .focused($captionFocused)
                    .lineLimit(3)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                // Visibility toggle
                HStack {
                    Text("Visible to")
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                    Picker("Visibility", selection: $vm.visibility) {
                        Text("This memory only").tag("this_item")
                        Text("All my memories").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Button {
                    captionFocused = false
                    Task { await vm.send() }
                } label: {
                    Text("Send")
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

// MARK: - Face Overlay

/// Draws highlight boxes around detected faces.
/// Coordinate flip: Vision uses bottom-left origin; SwiftUI uses top-left.
struct FaceOverlayView: View {
    let faces: [CGRect]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                let flipped = CGRect(
                    x:      face.minX * geo.size.width,
                    y:      (1 - face.maxY) * geo.size.height,
                    width:  face.width  * geo.size.width,
                    height: face.height * geo.size.height
                )
                Rectangle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    .frame(width: flipped.width, height: flipped.height)
                    .position(x: flipped.midX, y: flipped.midY)
            }
        }
    }
}

// MARK: - Step: Sending

struct SendingStep: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
            Text("Sending…")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }
}

// MARK: - Step: Sent ✓

struct SentStep: View {
    let vm: SendFlowViewModel
    let dismiss: () -> Void
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Accent checkmark — emotional peak
            ZStack {
                Circle()
                    .fill(Color.mtAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.mtAccent)
            }

            Text("Sent")
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text("Tap the link below to invite them\nif they're not on Memory Tunnel yet.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if let url = vm.createdInvitation?.shareURL {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
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

            Button("Done") { dismiss() }
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)

            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Error

struct ErrorStep: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("Something went wrong")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
            Text(message)
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
