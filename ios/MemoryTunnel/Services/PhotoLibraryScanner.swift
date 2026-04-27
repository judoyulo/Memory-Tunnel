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

                // Parallel batched processing: image load + face detect + embed run
                // concurrently per batch. Clustering remains serial because each new face
                // needs to be matched against the current set of centroids.
                let batchSize = 6
                var batchIndex = 0

                while batchIndex < assetList.count {
                    if Date() > deadline { break }
                    if Task.isCancelled { break }
                    let clusterCount = clusters.filter { $0.count >= minAppearances }.count
                    if photosProcessed >= minPhotos && clusterCount >= targetClusters { break }

                    let batchEnd = min(batchIndex + batchSize, assetList.count)
                    let batchAssets = Array(assetList[batchIndex..<batchEnd])

                    let results: [PhotoFaceResult] = await withTaskGroup(of: PhotoFaceResult?.self) { group in
                        for asset in batchAssets {
                            group.addTask {
                                guard let image = await self.loadImage(for: asset, targetSize: 1024) else { return nil }
                                guard let cgImage = image.cgImage else { return nil }
                                let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
                                var faces: [PhotoFaceResult.Face] = []
                                for obs in observations {
                                    if let r = await FaceEmbeddingService.shared.embedding(for: obs, in: cgImage) {
                                        faces.append(.init(embedding: r.embedding, crop: r.crop, method: r.method))
                                    }
                                }
                                return PhotoFaceResult(asset: asset, faces: faces)
                            }
                        }
                        var collected: [PhotoFaceResult] = []
                        for await res in group { if let r = res { collected.append(r) } }
                        return collected
                    }

                    // Serial clustering of all faces in this batch
                    for result in results {
                        photosProcessed += 1
                        for face in result.faces {
                            facesDetected += 1
                            if face.method == .aligned { facesAligned += 1 }

                            // Centroid-based clustering
                            var bestIdx: Int?
                            var bestSim: Float = -1
                            for (i, cluster) in clusters.enumerated() {
                                let sim = FaceEmbeddingService.shared.cosineSimilarity(face.embedding, cluster.centroid)
                                if sim > bestSim { bestSim = sim; bestIdx = i }
                            }

                            if let idx = bestIdx, bestSim >= FaceEmbeddingService.matchThreshold {
                                clusters[idx].count += 1
                                clusters[idx].assets.append(result.asset)
                                clusters[idx].addEmbedding(face.embedding)
                                if clusters[idx].bestCrop == nil {
                                    clusters[idx].bestCrop = face.crop
                                    clusters[idx].bestCropEmbedding = face.embedding
                                }
                            } else {
                                clusters.append(LocalCluster(
                                    id: UUID(),
                                    centroid: face.embedding,
                                    embeddingSum: face.embedding,
                                    embeddings: [face.embedding],
                                    count: 1,
                                    bestCrop: face.crop,
                                    assets: [result.asset],
                                    bestCropEmbedding: face.embedding
                                ))
                            }
                        }
                    }

                    PhotoLibraryScanner.scanProgress.update(scanned: photosProcessed, total: totalPhotos)

                    photosSinceLastEmit += batchAssets.count
                    if photosSinceLastEmit >= emitInterval {
                        photosSinceLastEmit = 0
                        mergeClusters(&clusters)
                        let snapshot = buildSuggestions(from: clusters, minAppearances: minAppearances, maxFaces: maxFaces)
                        if !snapshot.isEmpty {
                            continuation.yield(snapshot)
                        }
                    }

                    batchIndex = batchEnd
                }

                // Final merge + emit
                mergeClusters(&clusters)
                splitWideClusters(&clusters)
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

    /// Per-asset result of the parallel face-extraction step (before clustering).
    private struct PhotoFaceResult {
        struct Face {
            let embedding: [Float]
            let crop: UIImage
            let method: FaceEmbeddingService.EmbeddingMethod
        }
        let asset: PHAsset
        let faces: [Face]
    }

    private struct LocalCluster {
        let id: UUID
        var centroid: [Float]       // L2-normalized average embedding
        var embeddingSum: [Float]   // Running sum for centroid calculation
        var embeddings: [[Float]]   // Individual member embeddings (for split pass)
        var count: Int
        var bestCrop: UIImage?
        var assets: [PHAsset]
        /// Best-crop's matching embedding — used as the "anchor" for sub-cluster splits.
        var bestCropEmbedding: [Float]?

        mutating func addEmbedding(_ emb: [Float]) {
            embeddings.append(emb)
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
                        clusters[i].embeddings.append(contentsOf: clusters[j].embeddings)
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

    /// Post-merge split pass: detects "drifted" clusters where the average member
    /// is too far from the centroid (indicating the cluster combined multiple
    /// identities) and splits them via 2-means.
    ///
    /// Uses cohesion threshold tighter than mergeThreshold so genuine same-person
    /// clusters with diverse views are NOT split unnecessarily.
    private func splitWideClusters(_ clusters: inout [LocalCluster]) {
        let cohesionFloor: Float = FaceEmbeddingService.matchThreshold - 0.05  // 0.25 by default
        var i = 0
        while i < clusters.count {
            let c = clusters[i]
            // Need at least 4 members to even consider a split
            guard c.embeddings.count >= 4 else { i += 1; continue }

            // Check cohesion: how far is the worst member from the centroid?
            let sims = c.embeddings.map {
                FaceEmbeddingService.shared.cosineSimilarity($0, c.centroid)
            }
            let minSim = sims.min() ?? 1.0
            // Cluster is cohesive enough — leave it alone.
            if minSim >= cohesionFloor { i += 1; continue }

            // Cluster is drifted. 2-means split.
            if let (a, b) = twoMeans(c.embeddings) {
                // Partition assets and embeddings into the two new clusters
                var aEmbs: [[Float]] = [], bEmbs: [[Float]] = []
                var aAssets: [PHAsset] = [], bAssets: [PHAsset] = []
                for (idx, emb) in c.embeddings.enumerated() {
                    let simA = FaceEmbeddingService.shared.cosineSimilarity(emb, a)
                    let simB = FaceEmbeddingService.shared.cosineSimilarity(emb, b)
                    if simA >= simB {
                        aEmbs.append(emb); aAssets.append(c.assets[idx])
                    } else {
                        bEmbs.append(emb); bAssets.append(c.assets[idx])
                    }
                }

                // Don't split if one side is empty or nearly empty
                guard aEmbs.count >= 2, bEmbs.count >= 2 else { i += 1; continue }

                let clusterA = clusterFrom(embeddings: aEmbs, assets: aAssets, bestCrop: c.bestCrop, bestCropEmbedding: c.bestCropEmbedding)
                let clusterB = clusterFrom(embeddings: bEmbs, assets: bAssets, bestCrop: nil, bestCropEmbedding: nil)

                clusters[i] = clusterA
                clusters.insert(clusterB, at: i + 1)
                i += 2
            } else {
                i += 1
            }
        }
    }

    /// 2-means: partition embeddings into 2 clusters by farthest-pair seed.
    /// Returns the two centroids, or nil if degenerate.
    private func twoMeans(_ embeddings: [[Float]]) -> ([Float], [Float])? {
        guard embeddings.count >= 2 else { return nil }
        // Seed: pick the two embeddings that are FARTHEST apart (lowest cosine sim).
        var lowestSim: Float = 1.0
        var seedA = 0, seedB = 1
        for i in 0 ..< embeddings.count {
            for j in (i + 1) ..< embeddings.count {
                let s = FaceEmbeddingService.shared.cosineSimilarity(embeddings[i], embeddings[j])
                if s < lowestSim { lowestSim = s; seedA = i; seedB = j }
            }
        }
        var a = embeddings[seedA]
        var b = embeddings[seedB]
        // 5 Lloyd iterations is plenty for 2-means in this regime
        for _ in 0 ..< 5 {
            var aSum = [Float](repeating: 0, count: a.count); var aCount = 0
            var bSum = [Float](repeating: 0, count: a.count); var bCount = 0
            for emb in embeddings {
                let simA = FaceEmbeddingService.shared.cosineSimilarity(emb, a)
                let simB = FaceEmbeddingService.shared.cosineSimilarity(emb, b)
                if simA >= simB {
                    for k in 0 ..< emb.count { aSum[k] += emb[k] }; aCount += 1
                } else {
                    for k in 0 ..< emb.count { bSum[k] += emb[k] }; bCount += 1
                }
            }
            guard aCount > 0, bCount > 0 else { return nil }
            a = normalize(aSum.map { $0 / Float(aCount) })
            b = normalize(bSum.map { $0 / Float(bCount) })
        }
        return (a, b)
    }

    private func normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    private func clusterFrom(embeddings: [[Float]], assets: [PHAsset], bestCrop: UIImage?, bestCropEmbedding: [Float]?) -> LocalCluster {
        var sum = [Float](repeating: 0, count: embeddings[0].count)
        for e in embeddings { for k in 0 ..< sum.count { sum[k] += e[k] } }
        let centroid = normalize(sum.map { $0 / Float(embeddings.count) })
        return LocalCluster(
            id: UUID(),
            centroid: centroid,
            embeddingSum: sum,
            embeddings: embeddings,
            count: embeddings.count,
            bestCrop: bestCrop,
            assets: assets,
            bestCropEmbedding: bestCropEmbedding
        )
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
