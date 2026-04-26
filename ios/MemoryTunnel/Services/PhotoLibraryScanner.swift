// PhotoLibraryScanner.swift
// Scans the user's photo library on-device to find frequently-appearing faces.
// Uses MobileFaceNet (via FaceEmbeddingService) for identity-grade face embeddings.
// All processing stays on-device — no biometric data, face crops, or embeddings
// are ever sent to the server.
//
// Scan strategy:
//   - Random sampling from full library (not most-recent-first) for broad coverage
//   - Adaptive: scans at least 500 photos, extends until 20+ clusters or library exhausted
//   - .highQualityFormat at 1024px for reliable face detection and embedding quality
//   - 60-second deadline with 5-second per-image timeout
//   - Centroid-based clustering with post-merge pass
//   - Progressive UI updates via AsyncStream

import Photos
import UIKit
import os.log

private let logger = Logger(subsystem: "com.memorytunnel.app", category: "PhotoScanner")

// MARK: - FaceSuggestion

struct FaceSuggestion: Identifiable {
    let id: UUID
    let sampleCrop: UIImage
    let recentAssets: [PHAsset]
    let count: Int
    /// Cluster centroid embedding (L2-normalized). The identity of this person.
    /// Used to link the face to the chapter so future scans recognize them correctly.
    let embedding: [Float]
    var name: String = ""
}

// MARK: - Scan Progress (thread-safe counters for UI)

// Observable progress tracker. Updated from any context via Task dispatch.
@MainActor
final class ScanProgressTracker: ObservableObject {
    @Published var scanned: Int = 0
    @Published var total: Int = 0

    nonisolated func update(scanned: Int, total: Int) {
        Task { @MainActor in
            self.scanned = scanned
            self.total = total
        }
    }
}

// MARK: - PhotoLibraryScanner

actor PhotoLibraryScanner {

    static let shared = PhotoLibraryScanner()
    @MainActor static let scanProgress = ScanProgressTracker()
    private init() {}

    // MARK: - Permission

    func requestAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - Progressive Scan

    /// Streams face suggestions as they are discovered during scanning.
    /// Uses MobileFaceNet embeddings for identity matching.
    /// Adaptive: scans at least `minPhotos`, extends until `targetClusters` or library exhausted.
    func scanFacesProgressively(
        minPhotos: Int = 500,
        maxPhotos: Int = 5000,
        targetClusters: Int = 20,
        maxFaces: Int = 50,
        minAppearances: Int = 2
    ) -> AsyncStream<[FaceSuggestion]> {
        AsyncStream { continuation in
            Task {
                let status = await requestAccess()
                guard status == .authorized || status == .limited else {
                    continuation.finish()
                    return
                }

                // Fetch ALL photo assets for random sampling
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

                var assetList: [PHAsset] = []
                allAssets.enumerateObjects { asset, _, _ in
                    assetList.append(asset)
                }

                guard !assetList.isEmpty else {
                    continuation.finish()
                    return
                }

                // Random shuffle for broad coverage across time periods
                assetList.shuffle()

                // Cap at maxPhotos
                if assetList.count > maxPhotos {
                    assetList = Array(assetList.prefix(maxPhotos))
                }

                let totalPhotos = assetList.count
                PhotoLibraryScanner.scanProgress.update(scanned: 0, total: totalPhotos)

                let scanStart = Date()
                let deadline = scanStart.addingTimeInterval(60)

                var clusters: [LocalCluster] = []
                var photosSinceLastEmit = 0
                let emitInterval = 5
                var photosProcessed = 0
                var facesDetected = 0
                var facesAligned = 0

                for (index, asset) in assetList.enumerated() {
                    // Check deadline
                    if Date() > deadline { break }

                    // Check if we have enough clusters and processed minimum
                    let clusterCount = clusters.filter { $0.count >= minAppearances }.count
                    if photosProcessed >= minPhotos && clusterCount >= targetClusters { break }

                    if index % 5 == 0 {
                        await Task.yield()
                        if Task.isCancelled { break }
                    }

                    // Load image at high quality for reliable face detection
                    guard let image = await loadImage(for: asset, targetSize: 1024) else { continue }
                    guard let cgImage = image.cgImage else { continue }
                    photosProcessed += 1
                    PhotoLibraryScanner.scanProgress.update(scanned: photosProcessed, total: totalPhotos)

                    // Detect faces + generate embeddings
                    let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
                    guard !observations.isEmpty else { continue }

                    for obs in observations {
                        guard let result = await FaceEmbeddingService.shared.embedding(
                            for: obs, in: cgImage
                        ) else { continue }

                        facesDetected += 1
                        if result.method == .aligned { facesAligned += 1 }

                        // Centroid-based clustering
                        var bestIdx: Int?
                        var bestSim: Float = -1
                        for (i, cluster) in clusters.enumerated() {
                            let sim = FaceEmbeddingService.shared.cosineSimilarity(
                                result.embedding, cluster.centroid
                            )
                            if sim > bestSim { bestSim = sim; bestIdx = i }
                        }

                        if let idx = bestIdx, bestSim >= FaceEmbeddingService.matchThreshold {
                            clusters[idx].count += 1
                            clusters[idx].assets.append(asset)
                            clusters[idx].addEmbedding(result.embedding)
                            if clusters[idx].bestCrop == nil { clusters[idx].bestCrop = result.crop }
                        } else {
                            clusters.append(LocalCluster(
                                id: UUID(),
                                centroid: result.embedding,
                                embeddingSum: result.embedding,
                                count: 1,
                                bestCrop: result.crop,
                                assets: [asset]
                            ))
                        }
                    }

                    photosSinceLastEmit += 1
                    if photosSinceLastEmit >= emitInterval {
                        photosSinceLastEmit = 0
                        // Post-merge before emitting
                        mergeClusters(&clusters)
                        let snapshot = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)
                        if !snapshot.isEmpty {
                            continuation.yield(snapshot)
                        }
                    }
                }

                // Final merge + emit
                mergeClusters(&clusters)
                let final = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)

                // Log scan summary
                let elapsed = Date().timeIntervalSince(scanStart)
                let clusterCount = final.count
                let alignPct = facesDetected > 0 ? Int(Double(facesAligned) / Double(facesDetected) * 100) : 0
                logger.info("Scan complete: \(photosProcessed) photos, \(facesDetected) faces (\(alignPct)% aligned), \(clusterCount) clusters, \(String(format: "%.1f", elapsed))s")

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

        var results: [FaceSuggestion] = []
        let stream = scanFacesProgressively(minPhotos: limit, maxPhotos: limit, maxFaces: topN)
        for await snapshot in stream {
            results = snapshot
        }
        return results
    }

    // MARK: - Private

    private struct LocalCluster {
        let id: UUID
        var centroid: [Float]       // L2-normalized average embedding
        var embeddingSum: [Float]   // Running sum for centroid calculation
        var count: Int
        var bestCrop: UIImage?
        var assets: [PHAsset]

        mutating func addEmbedding(_ emb: [Float]) {
            for i in 0 ..< embeddingSum.count { embeddingSum[i] += emb[i] }
            // Recompute centroid: average then L2-normalize
            var avg = embeddingSum.map { $0 / Float(count) }
            var norm: Float = 0
            for x in avg { norm += x * x }
            norm = norm.squareRoot()
            if norm > 0 { avg = avg.map { $0 / norm } }
            centroid = avg
        }
    }

    /// Post-clustering merge: merge clusters whose centroids are similar.
    private func mergeClusters(_ clusters: inout [LocalCluster]) {
        var merged = true
        while merged {
            merged = false
            for i in 0 ..< clusters.count {
                for j in (i + 1) ..< clusters.count {
                    let sim = FaceEmbeddingService.shared.cosineSimilarity(
                        clusters[i].centroid, clusters[j].centroid
                    )
                    if sim >= FaceEmbeddingService.mergeThreshold {
                        clusters[i].count += clusters[j].count
                        clusters[i].assets.append(contentsOf: clusters[j].assets)
                        for k in 0 ..< clusters[i].embeddingSum.count {
                            clusters[i].embeddingSum[k] += clusters[j].embeddingSum[k]
                        }
                        // Recompute centroid
                        var avg = clusters[i].embeddingSum.map { $0 / Float(clusters[i].count) }
                        var norm: Float = 0
                        for x in avg { norm += x * x }
                        norm = norm.squareRoot()
                        if norm > 0 { avg = avg.map { $0 / norm } }
                        clusters[i].centroid = avg
                        clusters.remove(at: j)
                        merged = true
                        break
                    }
                }
                if merged { break }
            }
        }
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
                    count: cluster.count,
                    embedding: cluster.centroid
                )
            }
    }

    private func loadImage(for asset: PHAsset, targetSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let size = CGSize(width: targetSize, height: targetSize)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false

            var resumed = false

            // 5-second per-image timeout
            let timeoutWork = DispatchWorkItem {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeoutWork)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                timeoutWork.cancel()
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
