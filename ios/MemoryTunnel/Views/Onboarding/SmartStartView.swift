// SmartStartView.swift
// Smart Start onboarding — suggests people from the user's photo library.
// Shown once after new-user name entry. Skipped for returning users.
//
// Privacy: all face processing is on-device. No crops, embeddings, or
// biometric data are sent to the server at any point in this flow.

import SwiftUI
import Photos

// MARK: - State

enum SmartStartState: Equatable {
    case intro
    case scanning
    case suggestions
    case photoPicker(Int)          // index into vm.suggestions
    case captioning(Int, UIImage)  // suggestion index + selected image
    case uploading
    case complete(chapterID: String, personName: String, shareURL: URL?)

    static func == (lhs: SmartStartState, rhs: SmartStartState) -> Bool {
        switch (lhs, rhs) {
        case (.intro, .intro), (.scanning, .scanning), (.suggestions, .suggestions),
             (.uploading, .uploading): return true
        case (.photoPicker(let a), .photoPicker(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SmartStartViewModel: ObservableObject {

    @Published var state: SmartStartState = .intro
    @Published var suggestions: [FaceSuggestion] = []
    @Published var scanTimedOut = false
    @Published var caption: String = ""
    @Published var detectedFaces: [CGRect] = []
    @Published var errorMessage: String?

    var onComplete: () -> Void = {}

    private var scanTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Permission + Scan

    func requestAndScan() {
        state = .scanning
        scanTimedOut = false

        // Timeout sentinel — stored so cancelScan() can cancel it too
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled {
                scanTimedOut = true
            }
        }

        scanTask = Task {
            let results = await PhotoLibraryScanner.shared.scanForFrequentFaces()

            if Task.isCancelled { return }

            timeoutTask?.cancel()

            if results.isEmpty {
                onComplete()
            } else {
                suggestions = results
                state = .suggestions
            }
        }
    }

    func cancelScan() {
        timeoutTask?.cancel()
        scanTask?.cancel()
        onComplete()
    }

    // MARK: - Suggestion name binding

    func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { self.suggestions[index].name },
            set: { self.suggestions[index].name = $0 }
        )
    }

    // MARK: - Face Photos Picker

    func openPhotoPicker(for index: Int) {
        state = .photoPicker(index)
    }

    // MARK: - Caption Step

    func selectPhoto(_ image: UIImage, forIndex index: Int) async {
        detectedFaces = await FaceDetectionService.detectFaces(in: image)
        state = .captioning(index, image)
    }

    // MARK: - Upload

    func send(index: Int, image: UIImage) async {
        guard index < suggestions.count else { return }
        let suggestion = suggestions[index]
        let name = suggestion.name.trimmingCharacters(in: .whitespaces)

        state = .uploading

        do {
            // 1. Create chapter
            let chapter = try await APIClient.shared.createChapter(
                name: name.isEmpty ? nil : name
            )
            let chapterID = chapter.id

            // 2. Compress
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                throw APIError.httpError(0, "Image compression failed")
            }

            // 3. Presign
            let presign = try await APIClient.shared.presign(chapterID: chapterID)

            // 4. Upload to S3
            try await APIClient.shared.uploadToS3(data: data, presign: presign)

            // 5. Create memory
            let memory = try await APIClient.shared.createMemory(
                chapterID:  chapterID,
                s3Key:      presign.s3Key,
                caption:    caption.isEmpty ? nil : caption,
                takenAt:    nil,
                visibility: "this_item"
            )

            // 6. Create invitation (non-fatal)
            let invitation = try? await APIClient.shared.createInvitation(
                chapterID: chapterID,
                memoryID:  memory.id
            )

            // 7. Fire-and-forget face indexing
            Task { await FaceIndexService.shared.processFaces(in: image) }

            state = .complete(
                chapterID: chapterID,
                personName: name.isEmpty ? "them" : name,
                shareURL: invitation?.shareURL
            )

        } catch {
            errorMessage = error.localizedDescription
            // Step back to captioning so user can retry
            if case .uploading = state {
                state = .captioning(index, image)
            }
        }
    }

    // MARK: - Completion

    func saveLater() {
        onComplete()
    }
}

// MARK: - Root View

struct SmartStartView: View {
    @StateObject private var vm = SmartStartViewModel()
    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            Group {
                switch vm.state {
                case .intro:
                    SmartStartIntroScreen(vm: vm)
                case .scanning:
                    SmartStartScanningScreen(vm: vm)
                case .suggestions:
                    SmartStartSuggestionsScreen(vm: vm)
                case .photoPicker(let index):
                    SmartStartPhotoPicker(vm: vm, suggestionIndex: index)
                case .captioning(let index, let image):
                    SmartStartCaptionScreen(vm: vm, suggestionIndex: index, image: image)
                case .uploading:
                    SmartStartUploadingScreen()
                case .complete(_, let name, let shareURL):
                    SmartStartCompleteScreen(vm: vm, personName: name, shareURL: shareURL)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.mtSlide, value: vm.state)
        }
        .onAppear {
            vm.onComplete = onComplete

            // Skip SmartStart for returning users or users who already have chapters
            let hasRun = UserDefaults.standard.bool(forKey: "smartStartCompleted")
            if hasRun { onComplete() }
        }
    }
}

// MARK: - Screen A: Pre-Permission Intro

private struct SmartStartIntroScreen: View {
    @ObservedObject var vm: SmartStartViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.mtAccent)

                VStack(spacing: Spacing.sm) {
                    Text("Who do you want\nto stay close to?")
                        .font(.mtEmptyTitle)
                        .foregroundStyle(Color.mtLabel)
                        .multilineTextAlignment(.center)

                    Text("Memory Tunnel can suggest\npeople from your photos —\non your device, privately.")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                Button {
                    vm.requestAndScan()
                } label: {
                    Text("Allow access to Photos")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .accessibilityLabel("Allow access to photos to find people you care about")

                Button {
                    UserDefaults.standard.set(true, forKey: "smartStartCompleted")
                    vm.onComplete()
                } label: {
                    Text("Skip this step")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }
                .accessibilityLabel("Skip face suggestions, open the app")
            }

            Spacer(minLength: Spacing.xl)
        }
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Screen B: Scanning

private struct SmartStartScanningScreen: View {
    @ObservedObject var vm: SmartStartViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.2)

                Text(vm.scanTimedOut
                     ? "This is taking longer than usual…"
                     : "Finding the people you care about…")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: vm.scanTimedOut)
            }

            Spacer()

            Button {
                vm.cancelScan()
            } label: {
                Text("Skip for now")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .stroke(Color.mtLabel, lineWidth: 1.5)
                    )
            }

            Spacer(minLength: Spacing.xl)
        }
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Screen C: Suggestions

private struct SmartStartSuggestionsScreen: View {
    @ObservedObject var vm: SmartStartViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("People from your photos")
                            .font(.mtEmptyTitle)
                            .foregroundStyle(Color.mtLabel)
                        Text("Start a chapter with someone who matters.")
                            .font(.mtBody)
                            .foregroundStyle(Color.mtSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.md)

                    Divider()
                        .background(Color.mtLabel.opacity(0.08))

                    ForEach(vm.suggestions.indices, id: \.self) { index in
                        FaceCardRow(
                            vm: vm,
                            index: index,
                            autoFocus: index == 0
                        )
                        Divider()
                            .background(Color.mtLabel.opacity(0.08))
                    }
                }
                // Bottom padding so content doesn't hide behind pinned button
                .padding(.bottom, 80)
            }

            // Pinned skip button
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.mtBackground.opacity(0), Color.mtBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)

                Button {
                    UserDefaults.standard.set(true, forKey: "smartStartCompleted")
                    vm.onComplete()
                } label: {
                    Text("Skip — I'll do this later")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
                .background(Color.mtBackground)
                .accessibilityLabel("Skip face suggestions, open the app")
            }
        }
    }
}

// MARK: - Face Card Row

private struct FaceCardRow: View {
    @ObservedObject var vm: SmartStartViewModel
    let index: Int
    let autoFocus: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let suggestion = vm.suggestions[index]
        let nameIsEmpty = suggestion.name.trimmingCharacters(in: .whitespaces).isEmpty

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                // Face crop circle
                Image(uiImage: suggestion.sampleCrop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .accessibilityLabel("Unrecognized person from your photos")

                // Name field — underline only style
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Their name", text: vm.nameBinding(for: index))
                        .font(.mtBody)
                        .foregroundStyle(Color.mtLabel)
                        .focused($focused)
                        .onAppear { if autoFocus { focused = true } }
                        .accessibilityLabel("Enter name for this person")

                    Rectangle()
                        .fill(focused ? Color.mtLabel : Color.mtLabel.opacity(0.2))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)

            // Start a chapter CTA
            Button {
                vm.openPhotoPicker(for: index)
            } label: {
                HStack {
                    Text("Start a chapter")
                    Image(systemName: "arrow.right")
                }
                .font(.mtButton)
                .foregroundStyle(nameIsEmpty ? Color.mtBackground.opacity(0.4) : Color.mtBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(nameIsEmpty ? Color.mtLabel.opacity(0.4) : Color.mtLabel)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .disabled(nameIsEmpty)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.md)
            .accessibilityLabel(
                nameIsEmpty
                ? "Enter a name to start a chapter"
                : "Start a chapter with \(suggestion.name)"
            )
        }
    }
}

// MARK: - Screen D: Face Photos Picker

struct SmartStartPhotoPicker: View {
    @ObservedObject var vm: SmartStartViewModel
    let suggestionIndex: Int

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                let assets = vm.suggestions[suggestionIndex].recentAssets

                if assets.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Text("No photos found")
                            .font(.mtTitle)
                            .foregroundStyle(Color.mtLabel)
                        Button("Go back") {
                            vm.state = .suggestions
                        }
                        .font(.mtButton)
                        .foregroundStyle(Color.mtSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                PHAssetThumbnailView(asset: asset)
                                    .aspectRatio(1, contentMode: .fit)
                                    .onTapGesture {
                                        Task {
                                            if let image = await loadFullImage(for: asset) {
                                                await vm.selectPhoto(image, forIndex: suggestionIndex)
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Photos with \(vm.suggestions[suggestionIndex].name.isEmpty ? "this person" : vm.suggestions[suggestionIndex].name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { vm.state = .suggestions }
                        .foregroundStyle(Color.mtSecondary)
                }
            }
        }
    }

    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

// MARK: - PHAsset Thumbnail

private struct PHAssetThumbnailView: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Color.mtSurface
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Color.mtSecondary.opacity(0.4))
            }
        }
        .clipped()
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let size = CGSize(width: 200, height: 200)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        let result: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
        thumbnail = result
    }
}

// MARK: - Screen E: Caption

private struct SmartStartCaptionScreen: View {
    @ObservedObject var vm: SmartStartViewModel
    let suggestionIndex: Int
    let image: UIImage
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtError)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()
                .overlay(FaceOverlayView(faces: vm.detectedFaces))

            VStack(alignment: .leading, spacing: Spacing.md) {
                TextField("Add a caption… (optional)", text: $vm.caption, axis: .vertical)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .focused($captionFocused)
                    .lineLimit(3)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                Button {
                    captionFocused = false
                    Task { await vm.send(index: suggestionIndex, image: image) }
                } label: {
                    Text("Save memory")
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

// MARK: - Screen: Uploading

private struct SmartStartUploadingScreen: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
            Text("Saving memory…")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }
}

// MARK: - Screen F: Complete

private struct SmartStartCompleteScreen: View {
    @ObservedObject var vm: SmartStartViewModel
    let personName: String
    let shareURL: URL?
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

            Text("Memory saved")
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text("Ready to invite \(personName)?")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            VStack(spacing: Spacing.md) {
                if let url = shareURL {
                    Button {
                        showShareSheet = true
                    } label: {
                        Text("Invite \(personName)")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.mtLabel)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .sheet(isPresented: $showShareSheet) {
                        ShareSheet(items: [url])
                            .onDisappear {
                                UserDefaults.standard.set(true, forKey: "smartStartCompleted")
                                vm.onComplete()
                            }
                    }
                }

                Button {
                    UserDefaults.standard.set(true, forKey: "smartStartCompleted")
                    vm.saveLater()
                } label: {
                    Text("Save for later")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }
            }

            Spacer(minLength: Spacing.xl)
        }
        .padding(.horizontal, Spacing.xl)
    }
}
