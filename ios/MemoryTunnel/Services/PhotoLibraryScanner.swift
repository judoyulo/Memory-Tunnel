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
                let deadline = scanStart.addingTimeInterval(120) // doubled from 60s

                var clusters: [LocalCluster] = []
                var photosSinceLastEmit = 0
                let emitInterval = 5
                var photosProcessed = 0
                var facesDetected = 0
                var facesAligned = 0

                // Pipeline image loading: 3 concurrent PHAsset loads keep the pipe full
                // while the previous photo's faces are being embedded and clustered. ~3x
                // throughput vs serial load for sparse iCloud-backed libraries.
                let concurrency = 3

                await withTaskGroup(of: (asset: PHAsset, image: UIImage?).self) { group in
                    var nextIndex = 0
                    @Sendable func enqueueNext() -> Bool {
                        guard nextIndex < assetList.count else { return false }
                        let asset = assetList[nextIndex]
                        nextIndex += 1
                        group.addTask { [weak self] in
                            let img = await self?.loadImage(for: asset, targetSize: 1024)
                            return (asset, img)
                        }
                        return true
                    }

                    // Prime the pipeline
                    for _ in 0 ..< concurrency { _ = enqueueNext() }

                    while let loaded = await group.next() {
                        if Task.isCancelled || Date() > deadline { break }

                        let clusterCount = clusters.filter { $0.count >= minAppearances }.count
                        if photosProcessed >= minPhotos && clusterCount >= targetClusters { break }

                        // Refill the queue
                        _ = enqueueNext()

                        guard let image = loaded.image, let cgImage = image.cgImage else { continue }
                        let asset = loaded.asset
                        photosProcessed += 1
                        PhotoLibraryScanner.scanProgress.update(scanned: photosProcessed, total: totalPhotos)

                        let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
                        guard !observations.isEmpty else { continue }

                        for obs in observations {
                            guard let result = await FaceEmbeddingService.shared.embedding(
                                for: obs, in: cgImage
                            ) else { continue }

                            facesDetected += 1
                            if result.method == .aligned { facesAligned += 1 }

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
                                    assets: [asset],
                                    members: [result.embedding]
                                ))
                            }
                        }

                        photosSinceLastEmit += 1
                        if photosSinceLastEmit >= emitInterval {
                            photosSinceLastEmit = 0
                            splitDriftedClusters(&clusters)
                            mergeClusters(&clusters)
                            let snapshot = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)
                            if !snapshot.isEmpty {
                                continuation.yield(snapshot)
                            }
                        }
                    }
                    group.cancelAll()
                }

                // Final merge + emit
                splitDriftedClusters(&clusters)
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
        /// All member embeddings. Lets us detect a too-spread cluster (drift) and
        /// split it into two via 2-means rather than letting bad clusters persist.
        var members: [[Float]]

        mutating func addEmbedding(_ emb: [Float]) {
            members.append(emb)
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

    /// Detect clusters where the worst-fitting member is far from the centroid (drift)
    /// and split them via 2-means clustering. Prevents siblings/parents-and-kids from
    /// staying merged once enough evidence accumulates.
    private func splitDriftedClusters(_ clusters: inout [LocalCluster]) {
        // A cluster is "drifted" if its weakest member is below match threshold against centroid
        let driftCutoff: Float = 0.40 // weaker than matchThreshold(0.45) → likely a different person

        var i = 0
        while i < clusters.count {
            let c = clusters[i]
            guard c.members.count >= 4 else { i += 1; continue }

            // Find weakest similarity to centroid
            var minSim: Float = 1.0
            for m in c.members {
                let s = FaceEmbeddingService.shared.cosineSimilarity(m, c.centroid)
                if s < minSim { minSim = s }
            }
            guard minSim < driftCutoff else { i += 1; continue }

            // Run 2-means: pick two seeds (most-distant pair), assign each member, recompute.
            var (seedA, seedB) = (c.members[0], c.members[1])
            var maxDist: Float = -1
            for a in c.members {
                for b in c.members {
                    let d = FaceEmbeddingService.shared.cosineSimilarity(a, b)
                    if d < maxDist || maxDist < 0 { maxDist = d; seedA = a; seedB = b }
                }
            }

            for _ in 0 ..< 5 { // 5 iters is plenty for 2 means
                var sumA = [Float](repeating: 0, count: seedA.count)
                var sumB = [Float](repeating: 0, count: seedB.count)
                var ca = 0, cb = 0
                for m in c.members {
                    let sa = FaceEmbeddingService.shared.cosineSimilarity(m, seedA)
                    let sb = FaceEmbeddingService.shared.cosineSimilarity(m, seedB)
                    if sa >= sb {
                        for k in 0 ..< m.count { sumA[k] += m[k] }
                        ca += 1
                    } else {
                        for k in 0 ..< m.count { sumB[k] += m[k] }
                        cb += 1
                    }
                }
                if ca > 0 { seedA = l2NormalizeStatic(sumA.map { $0 / Float(ca) }) }
                if cb > 0 { seedB = l2NormalizeStatic(sumB.map { $0 / Float(cb) }) }
            }

            // Final assignment
            var membersA: [[Float]] = [], membersB: [[Float]] = []
            var assetsA: [PHAsset] = [], assetsB: [PHAsset] = []
            var sumA = [Float](repeating: 0, count: seedA.count)
            var sumB = [Float](repeating: 0, count: seedB.count)
            for (idx, m) in c.members.enumerated() {
                let sa = FaceEmbeddingService.shared.cosineSimilarity(m, seedA)
                let sb = FaceEmbeddingService.shared.cosineSimilarity(m, seedB)
                if sa >= sb {
                    membersA.append(m); for k in 0..<m.count { sumA[k] += m[k] }
                    if idx < c.assets.count { assetsA.append(c.assets[idx]) }
                } else {
                    membersB.append(m); for k in 0..<m.count { sumB[k] += m[k] }
                    if idx < c.assets.count { assetsB.append(c.assets[idx]) }
                }
            }

            // Don't split if one side is degenerate (< 2 members)
            guard membersA.count >= 2 && membersB.count >= 2 else { i += 1; continue }

            let clusterA = LocalCluster(
                id: UUID(), centroid: seedA, embeddingSum: sumA,
                count: membersA.count, bestCrop: c.bestCrop, assets: assetsA, members: membersA
            )
            let clusterB = LocalCluster(
                id: UUID(), centroid: seedB, embeddingSum: sumB,
                count: membersB.count, bestCrop: nil, assets: assetsB, members: membersB
            )
            clusters[i] = clusterA
            clusters.insert(clusterB, at: i + 1)
            i += 2
        }
    }

    private func l2NormalizeStatic(_ v: [Float]) -> [Float] {
        var s: Float = 0
        for x in v { s += x * x }
        let n = s.squareRoot()
        guard n > 0 else { return v }
        return v.map { $0 / n }
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
                        clusters[i].members.append(contentsOf: clusters[j].members)
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
