// PhotoLibraryScanner.swift
// Scans the user's photo library on-device to find frequently-appearing faces.
// All processing stays on-device — no biometric data, face crops, or embeddings
// are ever sent to the server.
//
// Usage: call scanForFrequentFaces() once during Smart Start onboarding.
// Results are [FaceSuggestion] — top faces by appearance count, ranked desc.

import Photos
import UIKit

// MARK: - FaceSuggestion

struct FaceSuggestion: Identifiable {
    let id: UUID               // local cluster ID (not persisted to FaceIndexService)
    let sampleCrop: UIImage    // best crop from the most-recent photo containing this face
    let recentAssets: [PHAsset] // all assets where this face was detected (for picker)
    var name: String = ""      // user-supplied name, filled in SmartStartView
}

// MARK: - PhotoLibraryScanner

actor PhotoLibraryScanner {

    static let shared = PhotoLibraryScanner()
    private init() {}

    // MARK: - Permission

    func requestAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - Scan

    /// Scan up to `limit` most-recent photos for faces.
    /// Returns the top `topN` people (min 2 appearances) sorted by frequency desc.
    /// Hard timeout: 10 seconds — returns whatever was collected so far.
    func scanForFrequentFaces(limit: Int = 150, topN: Int = 5) async -> [FaceSuggestion] {
        let status = await requestAccess()
        guard status == .authorized || status == .limited else { return [] }

        // Fetch up to `limit` most-recent image assets
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        // Collect all PHAsset objects into an array
        var assetList: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetList.append(asset)
        }

        guard !assetList.isEmpty else { return [] }

        // In-memory face clusters — never writes to FaceStore.
        // Each cluster represents one person, identified by L2 distance on landmark descriptors.
        // This works for new users (empty FaceStore) and avoids flooding FaceTaggingBanner.
        struct LocalCluster {
            let id: UUID
            let descriptor: [Float]
            var count: Int
            var bestCrop: UIImage?
            var assets: [PHAsset]
        }
        var clusters: [LocalCluster] = []
        let threshold = FaceIndexService.clusterThreshold

        // Process with a 10-second hard timeout
        let deadline = Date().addingTimeInterval(10)

        for (index, asset) in assetList.enumerated() {
            if Date() > deadline { break }

            // Cancel cooperative point every 10 assets
            if index % 10 == 0 {
                await Task.yield()
                if Task.isCancelled { break }
            }

            guard let image = await loadImage(for: asset, targetSize: 512) else { continue }

            // detectDescriptors: Vision landmark extraction only — no FaceStore reads or writes.
            // Clustering happens here in-memory so no FaceRecords are created for strangers.
            let descriptors = await FaceIndexService.shared.detectDescriptors(in: image)

            for (descriptor, crop) in descriptors {
                // Find nearest existing cluster within threshold
                var bestIdx: Int?
                var bestDist = Float.infinity
                for (i, cluster) in clusters.enumerated() {
                    let dist = FaceIndexService.shared.l2Distance(descriptor, cluster.descriptor)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }

                if let idx = bestIdx, bestDist <= threshold {
                    clusters[idx].count += 1
                    clusters[idx].assets.append(asset)
                    if clusters[idx].bestCrop == nil { clusters[idx].bestCrop = crop }
                } else {
                    clusters.append(LocalCluster(
                        id:         UUID(),
                        descriptor: descriptor,
                        count:      1,
                        bestCrop:   crop,
                        assets:     [asset]
                    ))
                }
            }
        }

        // Filter: at least 2 appearances, sort descending by count, take top N
        let suggestions = clusters
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .prefix(topN)
            .compactMap { cluster -> FaceSuggestion? in
                guard let crop = cluster.bestCrop else { return nil }
                return FaceSuggestion(
                    id: cluster.id,
                    sampleCrop: crop,
                    recentAssets: cluster.assets
                )
            }

        return Array(suggestions)
    }

    // MARK: - Private Helpers

    private func loadImage(for asset: PHAsset, targetSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let size = CGSize(width: targetSize, height: targetSize)
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // iCloud-only asset: isNetworkAccessAllowed = false means PhotoKit fires
                // the callback exactly once with isDegraded = true and never again —
                // leaving the continuation permanently suspended. Resume with nil immediately.
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if isInCloud {
                    continuation.resume(returning: nil)
                    return
                }
                // Only resume on the final (non-degraded) local result
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
