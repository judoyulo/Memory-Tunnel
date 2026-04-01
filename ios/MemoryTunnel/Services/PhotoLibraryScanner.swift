// PhotoLibraryScanner.swift
// Scans the user's photo library on-device to find frequently-appearing faces.
// All processing stays on-device — no biometric data, face crops, or embeddings
// are ever sent to the server.
//
// Usage: call scanFacesProgressively() for the new bubble onboarding (streams results
// as faces are discovered). Legacy scanForFrequentFaces() still available.

import Photos
import UIKit

// MARK: - FaceSuggestion

struct FaceSuggestion: Identifiable {
    let id: UUID               // local cluster ID (not persisted to FaceIndexService)
    let sampleCrop: UIImage    // best crop from the most-recent photo containing this face
    let recentAssets: [PHAsset] // all assets where this face was detected (for picker)
    let count: Int             // number of photos containing this face (for bubble sizing)
    var name: String = ""      // user-supplied name, filled in onboarding
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

    // MARK: - Progressive Scan (for face bubbles)

    /// Streams face suggestions as they are discovered during scanning.
    /// Bubbles appear progressively in the UI, biggest first.
    /// Scans up to `limit` photos, emits clusters with >= `minAppearances`, max `maxFaces`.
    func scanFacesProgressively(
        limit: Int = 500,
        maxFaces: Int = 30,
        minAppearances: Int = 2
    ) -> AsyncStream<[FaceSuggestion]> {
        AsyncStream { continuation in
            Task {
                let status = await requestAccess()
                guard status == .authorized || status == .limited else {
                    continuation.finish()
                    return
                }

                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.fetchLimit = limit
                let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

                var assetList: [PHAsset] = []
                assets.enumerateObjects { asset, _, _ in
                    assetList.append(asset)
                }

                guard !assetList.isEmpty else {
                    continuation.finish()
                    return
                }

                var clusters: [LocalCluster] = []
                let threshold = FaceIndexService.clusterThreshold
                let deadline = Date().addingTimeInterval(10)

                // Emit snapshot every N photos processed
                var photosSinceLastEmit = 0
                let emitInterval = 15

                for (index, asset) in assetList.enumerated() {
                    if Date() > deadline { break }

                    if index % 10 == 0 {
                        await Task.yield()
                        if Task.isCancelled { break }
                    }

                    guard let image = await loadImage(for: asset, targetSize: 512) else { continue }
                    let descriptors = await FaceIndexService.shared.detectDescriptors(in: image)

                    for (descriptor, crop) in descriptors {
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

                    photosSinceLastEmit += 1
                    if photosSinceLastEmit >= emitInterval {
                        photosSinceLastEmit = 0
                        let snapshot = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)
                        if !snapshot.isEmpty {
                            continuation.yield(snapshot)
                        }
                    }
                }

                // Final emit
                let final = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)
                continuation.yield(final)
                continuation.finish()
            }
        }
    }

    // MARK: - Legacy (batch scan)

    /// Batch scan — returns all results at once. Used by legacy SmartStartView.
    func scanForFrequentFaces(limit: Int = 500, topN: Int = 30) async -> [FaceSuggestion] {
        let status = await requestAccess()
        guard status == .authorized || status == .limited else { return [] }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var assetList: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetList.append(asset)
        }

        guard !assetList.isEmpty else { return [] }

        var clusters: [LocalCluster] = []
        let threshold = FaceIndexService.clusterThreshold
        let deadline = Date().addingTimeInterval(10)

        for (index, asset) in assetList.enumerated() {
            if Date() > deadline { break }
            if index % 10 == 0 {
                await Task.yield()
                if Task.isCancelled { break }
            }

            guard let image = await loadImage(for: asset, targetSize: 512) else { continue }
            let descriptors = await FaceIndexService.shared.detectDescriptors(in: image)

            for (descriptor, crop) in descriptors {
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

        return buildSuggestions(from: clusters, minAppearances: 2, maxFaces: topN)
    }

    // MARK: - Private

    private struct LocalCluster {
        let id: UUID
        let descriptor: [Float]
        var count: Int
        var bestCrop: UIImage?
        var assets: [PHAsset]
    }

    private func buildSuggestions(from clusters: [LocalCluster], minAppearances: Int, maxFaces: Int) -> [FaceSuggestion] {
        clusters
            .filter { $0.count >= minAppearances }
            .sorted { $0.count > $1.count }
            .prefix(maxFaces)
            .compactMap { cluster -> FaceSuggestion? in
                guard let crop = cluster.bestCrop else { return nil }
                return FaceSuggestion(
                    id: cluster.id,
                    sampleCrop: crop,
                    recentAssets: cluster.assets,
                    count: cluster.count
                )
            }
    }

    private func loadImage(for asset: PHAsset, targetSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let size = CGSize(width: targetSize, height: targetSize)
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if isInCloud {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }
                if image != nil {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
