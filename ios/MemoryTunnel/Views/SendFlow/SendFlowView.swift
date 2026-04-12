import SwiftUI
import PhotosUI
import CoreLocation
import ImageIO

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

    // EXIF metadata prefilled from photo
    @Published var locationName: String = ""
    @Published var eventDate: Date?
    @Published var emotionTags: Set<String> = []
    @Published var photoWidth: Int?
    @Published var photoHeight: Int?
    private var photoTakenAt: Date?

    let chapterID: String
    var createdInvitation: Invitation?

    init(chapterID: String) { self.chapterID = chapterID }

    // MARK: - Actions

    func loadSelectedImage() async {
        guard let item = selectedItem,
              let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        selectedImage = image
        photoWidth = Int(image.size.width * image.scale)
        photoHeight = Int(image.size.height * image.scale)
        step = .addCaption

        // Extract EXIF metadata (creation date + location) from the photo
        await extractPhotoMetadata(from: data)

        // On-device face detection (async, non-blocking)
        detectedFaces = await FaceDetectionService.detectFaces(in: image)
    }

    /// Read EXIF/IPTC metadata from photo data to prefill date and location
    private func extractPhotoMetadata(from data: Data) async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return }

        // Extract date from EXIF
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = formatter.date(from: dateStr) {
                photoTakenAt = date
                eventDate = date
            }
        }

        // Extract GPS location
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            var lat = gps[kCGImagePropertyGPSLatitude as String] as? Double ?? 0
            var lng = gps[kCGImagePropertyGPSLongitude as String] as? Double ?? 0
            if let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String, latRef == "S" { lat = -lat }
            if let lngRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String, lngRef == "W" { lng = -lng }

            if lat != 0 || lng != 0 {
                // Reverse geocode to get a place name
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: lat, longitude: lng)
                if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                    let parts = [placemark.locality, placemark.country].compactMap { $0 }
                    if !parts.isEmpty {
                        locationName = parts.joined(separator: ", ")
                    }
                }
            }
        }
    }

    func send() async {
        guard case .addCaption = step else { return }
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

            // 3. Create the Memory record (with EXIF-prefilled metadata)
            let memory = try await APIClient.shared.createMemory(
                chapterID:    chapterID,
                s3Key:        presign.s3Key,
                caption:      caption.isEmpty ? nil : caption,
                takenAt:      photoTakenAt,
                visibility:   visibility,
                locationName: locationName.isEmpty ? nil : locationName,
                width:        photoWidth,
                height:       photoHeight
            )

            // 4. Create invitation (generates share URL for Branch.io)
            createdInvitation = try? await APIClient.shared.createInvitation(
                chapterID: chapterID,
                memoryID:  memory.id
            )

            step = .sent

            // Fire-and-forget: index faces in the uploaded photo for the tagging prompt queue.
            Task { await FaceEmbeddingService.shared.processFaces(in: image) }
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
                        Button(L.cancel) { dismiss() }
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
    @State private var showSuggestedPhotos = false
    @State private var partnerEmbedding: [Float]?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text(L.chooseAPhoto)
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            PhotosPicker(selection: $vm.selectedItem, matching: .images) {
                Label(L.openPhotos, systemImage: "photo.on.rectangle")
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

            // Auto-scan: find photos with this person's face
            Button {
                Task {
                    // Try chapter tagged faces first, then partner ID
                    partnerEmbedding = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: vm.chapterID)
                    if partnerEmbedding == nil {
                        // No tagged faces — try to get from any partner in this chapter
                        if let partnerID = await loadPartnerID(chapterID: vm.chapterID) {
                            partnerEmbedding = await FaceEmbeddingService.shared.embeddingForPartner(partnerID: partnerID)
                        }
                    }
                    showSuggestedPhotos = true
                }
            } label: {
                Label(L.findMorePhotos, systemImage: "sparkle.magnifyingglass")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .stroke(Color.mtLabel, lineWidth: 1.5)
                    )
            }
            .padding(.horizontal, Spacing.xl)

            Text(L.scanForSamePerson)
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .sheet(isPresented: $showSuggestedPhotos) {
            SuggestedPhotosView(
                chapterID: vm.chapterID,
                partnerName: "them",
                directEmbedding: partnerEmbedding
            ) { selectedAssets in
                showSuggestedPhotos = false
                guard let asset = selectedAssets.first else { return }
                Task {
                    let options = PHImageRequestOptions()
                    options.deliveryMode = .highQualityFormat
                    options.isSynchronous = false
                    options.isNetworkAccessAllowed = true

                    let image: UIImage? = await withCheckedContinuation { cont in
                        var resumed = false
                        PHImageManager.default().requestImage(
                            for: asset,
                            targetSize: CGSize(width: 1200, height: 1200),
                            contentMode: .aspectFit,
                            options: options
                        ) { img, info in
                            guard !resumed else { return }
                            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                            if !isDegraded { resumed = true; cont.resume(returning: img) }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            guard !resumed else { return }
                            resumed = true
                            cont.resume(returning: nil)
                        }
                    }

                    if let image {
                        vm.selectedImage = image
                        vm.photoWidth = Int(image.size.width * image.scale)
                        vm.photoHeight = Int(image.size.height * image.scale)
                        vm.step = .addCaption
                        vm.detectedFaces = await FaceDetectionService.detectFaces(in: image)
                    }
                }
            }
        }
    }

    private func loadPartnerID(chapterID: String) async -> String? {
        // Try to get chapters from app state
        // Fallback: load from API
        let chapters = try? await APIClient.shared.chapters()
        return chapters?.first(where: { $0.id == chapterID })?.partner?.id
    }
}

// MARK: - Step: Add Caption

struct CaptionStep: View {
    @ObservedObject var vm: SendFlowViewModel
    @FocusState private var captionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            // Preview
            if let image = vm.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .overlay(FaceOverlayView(faces: vm.detectedFaces))
            }

            // Caption input + metadata
            VStack(alignment: .leading, spacing: Spacing.md) {
                TextField(L.captionOptional, text: $vm.caption, axis: .vertical)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .focused($captionFocused)
                    .lineLimit(3)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                // Metadata (prefilled from EXIF)
                MemoryMetadataFields(
                    locationName: $vm.locationName,
                    eventDate: $vm.eventDate,
                    emotionTags: $vm.emotionTags
                )

                // Visibility toggle
                HStack {
                    Text(L.visibleTo)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                    Picker(L.visibility, selection: $vm.visibility) {
                        Text(L.thisMemoryOnly).tag("this_item")
                        Text(L.allMyMemories).tag("all")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Button {
                    captionFocused = false
                    Task { await vm.send() }
                } label: {
                    Text(L.send)
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
            }
            .padding(Spacing.md)
            }
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
            Text(L.sending)
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

            Text(L.sent)
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text(L.inviteViaTap)
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

struct ErrorStep: View {
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

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
