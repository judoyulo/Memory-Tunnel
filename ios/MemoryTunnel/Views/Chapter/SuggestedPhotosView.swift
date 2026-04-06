// SuggestedPhotosView.swift
// Scans the user's photo library for photos containing a specific person's face
// that haven't been added to the chapter yet. User selects photos to add.

import SwiftUI
import Photos

@MainActor
final class SuggestedPhotosViewModel: ObservableObject {
    @Published var suggestions: [PHAsset] = []
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var scanProgress: String = "Scanning your photos..."

    let chapterID: String
    let partnerName: String

    /// The target embedding to match against. Set via init or resolved from chapter.
    var targetEmbedding: [Float]?

    init(chapterID: String, partnerName: String, directEmbedding: [Float]?) {
        self.chapterID = chapterID
        self.partnerName = partnerName
        self.targetEmbedding = directEmbedding
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        // Resolve embedding from chapter if not provided directly
        if targetEmbedding == nil && !chapterID.isEmpty {
            targetEmbedding = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: chapterID)
        }

        guard let target = targetEmbedding else {
            scanProgress = "No face to search for"
            return
        }

        let status = await PhotoLibraryScanner.shared.requestAccess()
        guard status == .authorized || status == .limited else {
            scanProgress = "Photo access denied"
            return
        }

        // Fetch ALL photos (no limit — we'll scan progressively)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var assetList: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in assetList.append(asset) }
        assetList.shuffle()

        guard !assetList.isEmpty else {
            scanProgress = "No photos found"
            return
        }

        let initialScanLimit = min(1000, assetList.count)
        let extendedScanLimit = min(5000, assetList.count)
        var scanned = 0
        var extended = false

        for (index, asset) in assetList.enumerated() {
            // Phase 1: first 1000 photos
            if scanned >= initialScanLimit && !extended {
                if suggestions.isEmpty {
                    // No results in 1000 — dig deeper
                    extended = true
                    scanProgress = "Digging deeper... this may take a moment"
                } else {
                    break // Found enough in initial scan
                }
            }

            // Phase 2: extended scan up to 5000
            if extended && scanned >= extendedScanLimit { break }

            if index % 10 == 0 {
                let total = extended ? extendedScanLimit : initialScanLimit
                scanProgress = extended
                    ? "Digging deeper... \(scanned)/\(total) (\(suggestions.count) found)"
                    : "Scanning \(scanned)/\(total)... (\(suggestions.count) found)"
                await Task.yield()
            }

            guard let image = await loadImage(for: asset),
                  let cgImage = image.cgImage else {
                scanned += 1
                continue
            }

            let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            scanned += 1
            guard !observations.isEmpty else { continue }

            for obs in observations {
                guard let result = await FaceEmbeddingService.shared.embedding(
                    for: obs, in: cgImage
                ) else { continue }

                let sim = FaceEmbeddingService.shared.cosineSimilarity(
                    result.embedding, target
                )
                if sim >= FaceEmbeddingService.matchThreshold {
                    // Stream result immediately — user sees photos as they're found
                    suggestions.append(asset)
                    break
                }
            }

            if suggestions.count >= 50 { break }
        }

        scanProgress = suggestions.isEmpty ? "No matching photos found" : "Found \(suggestions.count) photos"
    }

    func toggleSelection(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false

            var resumed = false
            let timeoutWork = DispatchWorkItem {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeoutWork)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                timeoutWork.cancel()
                guard !resumed else { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if isInCloud { resumed = true; continuation.resume(returning: nil); return }
                if image != nil { resumed = true; continuation.resume(returning: image) }
            }
        }
    }
}

// MARK: - View

struct SuggestedPhotosView: View {
    @StateObject private var vm: SuggestedPhotosViewModel
    let chapterID: String
    let onAdd: ([PHAsset]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(chapterID: String, partnerName: String, partnerCrop: UIImage? = nil, directEmbedding: [Float]? = nil, onAdd: @escaping ([PHAsset]) -> Void) {
        _vm = StateObject(wrappedValue: SuggestedPhotosViewModel(
            chapterID: chapterID,
            partnerName: partnerName,
            directEmbedding: directEmbedding
        ))
        self.chapterID = chapterID
        self.onAdd = onAdd
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                if vm.isScanning && vm.suggestions.isEmpty {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text(vm.scanProgress)
                            .font(.mtCaption)
                            .foregroundStyle(Color.mtSecondary)
                    }
                } else if vm.suggestions.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.mtTertiary)
                        Text(vm.scanProgress)
                            .font(.mtBody)
                            .foregroundStyle(Color.mtSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(vm.suggestions, id: \.localIdentifier) { asset in
                                SuggestedPhotoCell(
                                    asset: asset,
                                    isSelected: vm.selected.contains(asset.localIdentifier),
                                    onTap: { vm.toggleSelection(asset) }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Photos of \(vm.partnerName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add \(vm.selected.count)") {
                        let selectedAssets = vm.suggestions.filter {
                            vm.selected.contains($0.localIdentifier)
                        }
                        onAdd(selectedAssets)
                        // Don't dismiss here — let the caller (onAdd) control navigation.
                        // When used as a sheet, the caller dismisses. When inline, caller changes step.
                    }
                    .fontWeight(.semibold)
                    .disabled(vm.selected.isEmpty)
                }
            }
            .task { await vm.scan() }
        }
    }
}

// MARK: - Photo Cell

struct SuggestedPhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Color.mtSurface
                        .aspectRatio(1, contentMode: .fill)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mtLabel)
                        .background(Circle().fill(Color.white))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        thumbnail = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !resumed, let image else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
