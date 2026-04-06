// FacePickerSheet.swift
// Unified face picker + chapter action flow.
// State machine: detecting → picking → naming → done
// No nested sheets — everything renders inline.

import SwiftUI
import Photos

struct FacePickerSheet: View {
    let preloadedPhoto: UIImage?
    let asset: PHAsset
    let preloadedFaces: [(crop: UIImage, embedding: [Float])]
    var knownChapterID: String?
    var knownChapterName: String?
    var excludeChapterIDs: Set<String> = []
    /// Called when user acts on this card (creates chapter or adds photo)
    var onActed: ((String, String) -> Void)?

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // State machine
    enum Step {
        case detecting
        case picking
        case naming
        case batchReview
        case adding
        case scanning
        case navigating(chapterID: String)
        case done(message: String, chapterID: String, chapterName: String)
    }

    @State private var step: Step = .detecting
    @State private var photo: UIImage?
    @State private var faces: [(crop: UIImage, embedding: [Float])] = []
    @State private var selectedIndex: Int?
    @State private var faceChapterMatches: [Int: (chapterID: String, partnerName: String)] = [:]
    @State private var chapterNameInput = ""
    @State private var isWorking = false

    // Persisted across steps (won't get lost when step changes)
    @State private var savedEmbedding: [Float]?
    @State private var savedCrop: UIImage?
    @State private var resultChapterID = ""
    @State private var resultChapterName = ""
    @State private var pendingAssets: [PHAsset] = []
    @State private var batchImages: [(image: UIImage, takenAt: Date?)] = []

    init(photo: UIImage?, asset: PHAsset, faces: [(crop: UIImage, embedding: [Float])], knownChapterID: String? = nil, knownChapterName: String? = nil, excludeChapterIDs: Set<String> = [], onActed: ((String, String) -> Void)? = nil) {
        self.preloadedPhoto = photo
        self.asset = asset
        self.preloadedFaces = faces
        self.knownChapterID = knownChapterID
        self.knownChapterName = knownChapterName
        self.excludeChapterIDs = excludeChapterIDs
        self.onActed = onActed
    }

    private var selectedFace: (crop: UIImage, embedding: [Float])? {
        guard let idx = selectedIndex, idx < faces.count else { return nil }
        return faces[idx]
    }

    private var matchedChapter: (chapterID: String, partnerName: String)? {
        // If a face is selected, use its match (or nil if no match for that face)
        if let idx = selectedIndex {
            return faceChapterMatches[idx] // nil if this specific face has no chapter
        }
        // No face selected yet — use known chapter from feed card
        if let id = knownChapterID, let name = knownChapterName { return (id, name) }
        return nil
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                switch step {
                case .detecting:
                    VStack { Spacer(); ProgressView(); Text("Detecting faces...").font(.mtCaption).foregroundStyle(Color.mtSecondary); Spacer() }

                case .picking:
                    pickingView

                case .naming:
                    namingView

                case .batchReview:
                    BatchPhotoReviewView(
                        chapterID: resultChapterID,
                        initialImages: batchImages,
                        embedded: true,
                        faceEmbedding: savedEmbedding
                    ) {
                        onActed?(resultChapterID, resultChapterName)
                        step = .done(message: "Photos Added", chapterID: resultChapterID, chapterName: resultChapterName)
                    }

                case .adding:
                    VStack { Spacer(); ProgressView(); Text("Adding photo...").font(.mtCaption).foregroundStyle(Color.mtSecondary); Spacer() }

                case .navigating:
                    EmptyView()

                case .scanning:
                    SuggestedPhotosView(
                        chapterID: resultChapterID,
                        partnerName: resultChapterName.isEmpty ? "this person" : resultChapterName,
                        directEmbedding: savedEmbedding
                    ) { assets in
                        pendingAssets = assets
                        if resultChapterID.isEmpty {
                            step = .naming
                        } else {
                            // Chapter exists — load images and go to batch review
                            Task {
                                var loaded: [(image: UIImage, takenAt: Date?)] = []
                                for a in assets {
                                    if let img = await loadFullImage(for: a) {
                                        loaded.append((image: img, takenAt: a.creationDate))
                                    }
                                }
                                batchImages = loaded
                                step = loaded.isEmpty ? .done(message: "No photos loaded", chapterID: resultChapterID, chapterName: resultChapterName) : .batchReview
                            }
                        }
                    }

                case .done(let message, let chapterID, let chapterName):
                    doneView(message: message, chapterID: chapterID, chapterName: chapterName)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .picking = step {
                        Button("Cancel") { dismiss() }
                    } else if case .naming = step {
                        Button("Cancel") { dismiss() }
                    } else if case .detecting = step {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task { await loadAndDetect() }
        }
    }

    // MARK: - Step: Picking

    private var pickingView: some View {
        VStack(spacing: Spacing.lg) {
            if faces.count > 1 {
                Text("Who is this?")
                    .font(.mtTitle)
                    .foregroundStyle(Color.mtLabel)
                    .padding(.top, Spacing.lg)

                if let photo {
                    Image(uiImage: photo)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, Spacing.md)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                            Button { selectedIndex = index } label: {
                                VStack(spacing: 4) {
                                    Image(uiImage: face.crop)
                                        .resizable().scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(selectedIndex == index ? Color.mtLabel : Color.clear, lineWidth: 3))
                                    if let match = faceChapterMatches[index] {
                                        Text(match.partnerName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Color.mtAccent)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            } else {
                if let face = faces.first {
                    Spacer()
                    Image(uiImage: face.crop)
                        .resizable().scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: Spacing.sm) {
                if let match = matchedChapter, !excludeChapterIDs.contains(match.chapterID) {
                    Button {
                        savedEmbedding = selectedFace?.embedding ?? faces.first?.embedding
                        savedCrop = selectedFace?.crop ?? faces.first?.crop
                        resultChapterID = match.chapterID
                        resultChapterName = match.partnerName
                        Task { await addToChapter(match.chapterID, name: match.partnerName) }
                    } label: {
                        Text("Add to \(match.partnerName)'s chapter")
                            .font(.mtButton).foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.mtLabel)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                } else if let match = matchedChapter, excludeChapterIDs.contains(match.chapterID) {
                    // Already added to this chapter
                    Text("Already in \(match.partnerName)'s chapter")
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtAccent)
                        .padding(.vertical, 8)
                } else {
                    Button {
                        savedEmbedding = selectedFace?.embedding ?? faces.first?.embedding
                        savedCrop = selectedFace?.crop ?? faces.first?.crop
                        step = .naming
                    } label: {
                        Text("Start a chapter")
                            .font(.mtButton).foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(selectedIndex != nil || faces.count <= 1 ? Color.mtLabel : Color.mtTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .disabled(faces.count > 1 && selectedIndex == nil)
                }

                // "Find more photos" moved to BatchPhotoReviewView
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Step: Naming

    private var namingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            if let crop = savedCrop {
                Image(uiImage: crop)
                    .resizable().scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            }

            Text("Name this chapter")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            TextField("Their name", text: $chapterNameInput)
                .font(.mtBody)
                .padding(12)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .padding(.horizontal, Spacing.xl)

            Spacer()

            Button {
                Task { await createChapter() }
            } label: {
                Text(isWorking ? "Creating..." : "Create chapter")
                    .font(.mtButton).foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(!chapterNameInput.isEmpty ? Color.mtLabel : Color.mtTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .disabled(chapterNameInput.isEmpty || isWorking)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Step: Done

    private func doneView(message: String, chapterID: String, chapterName: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.mtAccent)

            Text(message)
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text(chapterName)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)

            Spacer()

            VStack(spacing: Spacing.sm) {
                // Done — dismiss back to card (card now shows "View in chapter" button)
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.mtButton).foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                Button {
                    step = .scanning
                } label: {
                    Label("Find more photos by scanning", systemImage: "sparkle.magnifyingglass")
                        .font(.mtButton).foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Color.mtLabel, lineWidth: 1.5))
                }

                Button { dismiss() } label: {
                    Text("Back to cards")
                        .font(.mtButton).foregroundStyle(Color.mtSecondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Actions

    private func loadAndDetect() async {
        if let preloadedPhoto {
            photo = preloadedPhoto
        } else {
            photo = await ReconnectionService.shared.loadFullImage(for: asset)
        }

        if !preloadedFaces.isEmpty {
            faces = preloadedFaces
        } else if let cgImage = photo?.cgImage {
            let obs = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            var detected: [(crop: UIImage, embedding: [Float])] = []
            for o in obs {
                if let r = await FaceEmbeddingService.shared.embedding(for: o, in: cgImage) {
                    detected.append((r.crop, r.embedding))
                }
            }
            faces = detected
        }

        if faces.count == 1 { selectedIndex = 0 }

        // Match faces to chapters
        let pickerThreshold: Float = 0.20
        for chapter in appState.chapters {
            let partnerID = chapter.partner?.id ?? chapter.id
            let name = chapter.partner?.displayName ?? chapter.name ?? "Unknown"
            var emb = await FaceEmbeddingService.shared.embeddingForPartner(partnerID: partnerID)
            if emb == nil { emb = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: chapter.id) }
            guard let partnerEmb = emb else { continue }
            for (i, face) in faces.enumerated() {
                let sim = FaceEmbeddingService.shared.cosineSimilarity(face.embedding, partnerEmb)
                if sim >= pickerThreshold {
                    faceChapterMatches[i] = (chapter.id, name)
                }
            }
        }

        step = .picking
    }

    private func createChapter() async {
        isWorking = true
        defer { isWorking = false }

        do {
            let chapter = try await APIClient.shared.createChapter(name: chapterNameInput)
            let partnerID = chapter.partner?.id ?? chapter.id

            if let emb = savedEmbedding {
                await FaceEmbeddingService.shared.linkFaceToChapter(
                    embedding: emb, crop: savedCrop,
                    partnerID: partnerID, chapterID: chapter.id
                )
            }

            resultChapterID = chapter.id
            resultChapterName = chapterNameInput

            // Build batch images: pending assets from scan + current card photo
            var batch: [(image: UIImage, takenAt: Date?)] = []
            for asset in pendingAssets {
                if let img = await loadFullImage(for: asset) {
                    batch.append((image: img, takenAt: asset.creationDate))
                }
            }
            if batch.isEmpty, let photo {
                batch.append((image: photo, takenAt: asset.creationDate))
            }
            pendingAssets = []

            if batch.isEmpty {
                onActed?(chapter.id, chapterNameInput)
                step = .done(message: "Chapter Created", chapterID: chapter.id, chapterName: chapterNameInput)
            } else {
                batchImages = batch
                step = .batchReview
            }
        } catch {
            print("[FacePicker] createChapter failed: \(error)")
        }
    }

    private func addToChapter(_ chapterID: String, name: String) async {
        resultChapterID = chapterID
        resultChapterName = name

        // Build batch: current card photo
        if let photo {
            batchImages = [(image: photo, takenAt: asset.creationDate)]
            step = .batchReview
        } else {
            step = .done(message: "What's next?", chapterID: chapterID, chapterName: name)
        }
    }

    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit, options: options
            ) { img, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded { resumed = true; continuation.resume(returning: img) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }
}
