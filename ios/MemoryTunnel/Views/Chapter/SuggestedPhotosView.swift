// SuggestedPhotosView.swift
// "Daily Dig" — scans a fresh batch of photos each session to find a person.
// Instead of scanning 5000 photos at once (slow), scans 1000 new photos per session.
// Previously found photos persist. Each session surfaces fresh finds.
// Turns a technical limit into a daily discovery mechanic.

import SwiftUI
import Photos

// MARK: - Persistence for daily dig

private enum DigStore {
    /// Asset IDs we've already scanned (per chapter). Avoids re-scanning.
    static func scannedIDs(for chapterID: String) -> Set<String> {
        let key = "dig.scanned.\(chapterID)"
        return Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func saveScannedIDs(_ ids: Set<String>, for chapterID: String) {
        let key = "dig.scanned.\(chapterID)"
        // Cap at 20,000 to avoid UserDefaults bloat
        let capped = ids.count > 20_000 ? Set(ids.prefix(20_000)) : ids
        UserDefaults.standard.set(Array(capped), forKey: key)
    }

    /// Asset IDs we've found matches in (per chapter). Shows instantly on reopen.
    static func foundIDs(for chapterID: String) -> [String] {
        let key = "dig.found.\(chapterID)"
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func saveFoundIDs(_ ids: [String], for chapterID: String) {
        let key = "dig.found.\(chapterID)"
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// Total library size (for coverage %)
    static func librarySize(for chapterID: String) -> Int {
        let key = "dig.libSize.\(chapterID)"
        return UserDefaults.standard.integer(forKey: key)
    }

    static func saveLibrarySize(_ size: Int, for chapterID: String) {
        let key = "dig.libSize.\(chapterID)"
        UserDefaults.standard.set(size, forKey: key)
    }
}

// MARK: - ViewModel

@MainActor
final class SuggestedPhotosViewModel: ObservableObject {
    @Published var suggestions: [PHAsset] = []
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var scanned: Int = 0
    @Published var scanTotal: Int = 0
    @Published var isDeepScan = false

    // Daily dig state
    @Published var todayFinds: Int = 0
    @Published var totalFinds: Int = 0
    @Published var coveragePercent: Int = 0
    @Published var scanComplete = false
    @Published var previouslyFoundIDs: Set<String> = []

    let chapterID: String
    let partnerName: String
    var targetEmbedding: [Float]?

    init(chapterID: String, partnerName: String, directEmbedding: [Float]?) {
        self.chapterID = chapterID
        self.partnerName = partnerName
        self.targetEmbedding = directEmbedding
    }

    func scan() async {
        isScanning = true
        defer {
            isScanning = false
            scanComplete = true
        }

        // Resolve embedding
        if targetEmbedding == nil && !chapterID.isEmpty {
            targetEmbedding = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: chapterID)
        }
        guard let target = targetEmbedding else { return }

        let status = await PhotoLibraryScanner.shared.requestAccess()
        guard status == .authorized || status == .limited else { return }

        // Fetch all photo assets
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var assetList: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in assetList.append(asset) }
        guard !assetList.isEmpty else { return }

        let librarySize = assetList.count
        DigStore.saveLibrarySize(librarySize, for: chapterID)

        // Load previously scanned + found IDs
        var alreadyScanned = DigStore.scannedIDs(for: chapterID)
        let previousFound = DigStore.foundIDs(for: chapterID)
        previouslyFoundIDs = Set(previousFound)

        // Load previously found assets immediately so user sees them
        if !previousFound.isEmpty {
            let fetchPrevious = PHAsset.fetchAssets(withLocalIdentifiers: previousFound, options: nil)
            var prevAssets: [PHAsset] = []
            fetchPrevious.enumerateObjects { a, _, _ in prevAssets.append(a) }
            suggestions = prevAssets
            totalFinds = prevAssets.count
        }

        // Filter to unscanned photos, shuffle for variety
        var freshAssets = assetList.filter { !alreadyScanned.contains($0.localIdentifier) }
        freshAssets.shuffle()

        // Daily batch: 1000 fresh photos
        let batchSize = min(1000, freshAssets.count)
        scanTotal = batchSize

        // Calculate coverage
        let totalScanned = alreadyScanned.count + batchSize
        coveragePercent = librarySize > 0 ? min(Int(Double(totalScanned) / Double(librarySize) * 100), 100) : 0

        if batchSize == 0 {
            // Entire library scanned across all sessions
            coveragePercent = 100
            scanComplete = true
            return
        }

        let batch = Array(freshAssets.prefix(batchSize))

        for (index, asset) in batch.enumerated() {
            if index % 10 == 0 {
                scanned = index
                await Task.yield()
            }

            alreadyScanned.insert(asset.localIdentifier)

            guard let image = await loadImage(for: asset),
                  let cgImage = image.cgImage else { continue }

            let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            guard !observations.isEmpty else { continue }

            for obs in observations {
                guard let result = await FaceEmbeddingService.shared.embedding(
                    for: obs, in: cgImage
                ) else { continue }

                let sim = FaceEmbeddingService.shared.cosineSimilarity(
                    result.embedding, target
                )
                if sim >= FaceEmbeddingService.matchThreshold {
                    suggestions.append(asset)
                    todayFinds += 1
                    totalFinds += 1
                    break
                }
            }

            if todayFinds >= 30 { break } // Cap per session
        }

        scanned = batchSize

        // Persist
        DigStore.saveScannedIDs(alreadyScanned, for: chapterID)
        let allFoundIDs = suggestions.map { $0.localIdentifier }
        DigStore.saveFoundIDs(allFoundIDs, for: chapterID)

        // Update coverage
        coveragePercent = librarySize > 0 ? min(Int(Double(alreadyScanned.count) / Double(librarySize) * 100), 100) : 0
    }

    func toggleSelection(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    func isNewFind(_ asset: PHAsset) -> Bool {
        !previouslyFoundIDs.contains(asset.localIdentifier)
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
                    ScanProgressRing(
                        scanned: vm.scanned,
                        total: vm.scanTotal,
                        facesFound: vm.todayFinds
                    )
                } else if vm.suggestions.isEmpty && vm.scanComplete {
                    // Nothing found across all sessions
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.mtTertiary)
                        Text(L.noPhotosYet)
                            .font(.mtBody)
                            .foregroundStyle(Color.mtSecondary)
                        if vm.coveragePercent < 100 {
                            Text(L.comeBackTomorrowDig)
                                .font(.mtCaption)
                                .foregroundStyle(Color.mtTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.xl)
                        }
                    }
                } else {
                    ScrollView {
                        // Status header
                        dailyDigHeader

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(vm.suggestions, id: \.localIdentifier) { asset in
                                SuggestedPhotoCell(
                                    asset: asset,
                                    isSelected: vm.selected.contains(asset.localIdentifier),
                                    isNewFind: vm.isNewFind(asset),
                                    onTap: { vm.toggleSelection(asset) }
                                )
                            }
                        }

                        // Bottom teaser
                        if vm.scanComplete && vm.coveragePercent < 100 {
                            VStack(spacing: 6) {
                                Text(L.comeBackMore)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.mtSecondary)
                                Text(L.tunnelKeepsDigging)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTertiary)
                            }
                            .padding(.vertical, Spacing.lg)
                        }
                    }
                }
            }
            .navigationTitle(L.photosOf(vm.partnerName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add \(vm.selected.count)") {
                        let selectedAssets = vm.suggestions.filter {
                            vm.selected.contains($0.localIdentifier)
                        }
                        onAdd(selectedAssets)
                    }
                    .fontWeight(.semibold)
                    .disabled(vm.selected.isEmpty)
                }
            }
            .task { await vm.scan() }
        }
    }

    // MARK: - Daily Dig Header

    @ViewBuilder
    private var dailyDigHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Scanning status or today's drop
                if vm.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(vm.scanned) / \(vm.scanTotal)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.mtTertiary)
                } else if vm.todayFinds > 0 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mtAccent)
                    Text(L.todaysDrop(vm.todayFinds))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.mtAccent)
                } else if vm.scanComplete {
                    Text(L.noNewFinds)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTertiary)
                }

                Spacer()

                // Coverage pill
                Text(L.tunneled(vm.coveragePercent))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(vm.coveragePercent >= 100 ? Color.mtAccent : Color.mtTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (vm.coveragePercent >= 100 ? Color.mtAccent : Color.mtLabel)
                            .opacity(0.08)
                    )
                    .clipShape(Capsule())
            }

            // Total count
            if vm.totalFinds > 0 && !vm.isScanning {
                HStack {
                    Text(L.totalPhotosFound(vm.totalFinds))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mtTertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Photo Cell

struct SuggestedPhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    var isNewFind: Bool = false
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

                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mtLabel)
                        .background(Circle().fill(Color.white))
                        .padding(6)
                }

                // "New" sparkle badge for today's finds
                if isNewFind && !isSelected {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                        Text(L.new)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.mtAccent)
                    .clipShape(Capsule())
                    .padding(4)
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
