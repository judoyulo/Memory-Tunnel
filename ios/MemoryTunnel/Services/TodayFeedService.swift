// TodayFeedService.swift
// Builds the Today Tab feed: a mix of photo cards from the user's library.
// Two card types, balanced 1:1:
//   1. "New face" — photos with people who don't have an existing chapter
//   2. "Unsaved memory" — photos with people who HAVE a chapter but this photo isn't in it
//
// Uses MobileFaceNet embeddings to match faces to chapter partners.

import Photos
import UIKit
import SwiftUI
import Vision
import os.log

private let logger = Logger(subsystem: "com.memorytunnel.app", category: "TodayFeed")

// MARK: - FeedCard

enum FeedCardType {
    case newFace
    case unsavedMemory
    case added  // User acted on this card (added to chapter or created one)
}

struct FeedCard: Identifiable {
    let id = UUID()
    var type: FeedCardType
    let asset: PHAsset
    let faceCrop: UIImage
    let faceObservation: VNFaceObservation
    let embedding: [Float]
    var matchedChapterID: String?
    var matchedPartnerName: String?
    var allChapterMatches: [(chapterID: String, partnerName: String)] = []
    var photoDepth: Int = 0  // How deep in the library this photo was found

    var tagText: String {
        switch type {
        case .newFace:       return L.newFace
        case .unsavedMemory: return L.unsavedMemory
        case .added:         return L.added
        }
    }

    var tagColor: Color {
        switch type {
        case .newFace:       return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .unsavedMemory: return Color.mtAccent
        case .added:         return Color(red: 0.298, green: 0.686, blue: 0.475) // green
        }
    }
}

// MARK: - TodayFeedService

actor TodayFeedService {

    static let shared = TodayFeedService()
    @MainActor static let scanProgress = ScanProgressTracker()
    private init() {}

    /// Max appearances per face in the feed. Multi-face photos get 2x allowance.
    private static let maxFaceAppearances = 3

    /// Build a shuffled feed of cards, balanced ~1:1 between new faces and unsaved memories.
    /// 20 cards per day.
    func buildFeed(
        chapters: [Chapter],
        maxCards: Int = 21
    ) async -> [FeedCard] {
        let status = await PhotoLibraryScanner.shared.requestAccess()
        guard status == .authorized || status == .limited else { return [] }

        // Auto-link chapters to faces (bootstrap face→chapter mapping)
        await FaceEmbeddingService.shared.autoLinkChapters(chapters: chapters)

        // Get embeddings for all chapter partners (try both partner ID and chapter ID)
        var partnerEmbeddings: [(chapterID: String, partnerName: String, embedding: [Float])] = []
        for chapter in chapters {
            let partnerID = chapter.partner?.id ?? chapter.id
            let partnerName = chapter.partner?.displayName ?? chapter.name ?? "Unknown"

            // Try partner ID first, then chapter ID
            var emb = await FaceEmbeddingService.shared.embeddingForPartner(partnerID: partnerID)
            if emb == nil {
                emb = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: chapter.id)
            }
            if let emb {
                partnerEmbeddings.append((
                    chapterID: chapter.id,
                    partnerName: partnerName,
                    embedding: emb
                ))
            }
        }

        // Fetch random photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var assetList: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in assetList.append(asset) }

        // Map each asset to its real library position (before shuffle)
        // Position 0 = most recent photo, position N = oldest
        var assetDepth: [String: Int] = [:]
        for (idx, asset) in assetList.enumerated() {
            assetDepth[asset.localIdentifier] = idx
        }
        let totalLibrarySize = assetList.count

        assetList.shuffle()

        let scanLimit = min(assetList.count, 1500)
        TodayFeedService.scanProgress.update(scanned: 0, total: scanLimit)

        var newFaceCards: [FeedCard] = []
        var unsavedMemoryCards: [FeedCard] = []

        // Track face appearance counts for diversity limit (with centroid averaging)
        var faceClusters: [[Float]] = []
        var faceAppearanceCounts: [Int] = []
        var faceClusterSums: [[Float]] = []

        // Pre-scan: find the user's face (most common face in first 50 photos with faces)
        var userFaceEmbedding: [Float]?
        var userFaceClusters: [[Float]] = []
        var userFaceCounts: [Int] = []
        var userFaceSums: [[Float]] = []
        var prescanCount = 0

        for i in 0 ..< min(scanLimit, 200) {
            let asset = assetList[i]
            guard let image = await loadImage(for: asset),
                  let cgImage = image.cgImage else { continue }
            let obs = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            for o in obs {
                guard let r = await FaceEmbeddingService.shared.embedding(for: o, in: cgImage) else { continue }
                let idx = findOrCreateCluster(r.embedding, clusters: &userFaceClusters, counts: &userFaceCounts, sums: &userFaceSums)
                userFaceCounts[idx] += 1
            }
            prescanCount += 1
            if prescanCount >= 50 { break }
        }
        // The most frequent face is likely the user
        if let maxIdx = userFaceCounts.enumerated().max(by: { $0.element < $1.element })?.offset,
           userFaceCounts[maxIdx] >= 5 {
            userFaceEmbedding = userFaceClusters[maxIdx]
        }

        for i in 0 ..< scanLimit {
            if (newFaceCards.count + unsavedMemoryCards.count) >= maxCards { break }

            let asset = assetList[i]

            if i % 10 == 0 {
                await Task.yield()
                TodayFeedService.scanProgress.update(scanned: i, total: scanLimit)
            }

            guard let image = await loadImage(for: asset),
                  let cgImage = image.cgImage else { continue }

            let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            guard !observations.isEmpty else { continue }

            let hasMultipleFaces = observations.count > 1

            // Skip photos that only contain the user's face (selfies)
            if !hasMultipleFaces, let userEmb = userFaceEmbedding {
                if let firstObs = observations.first,
                   let firstResult = await FaceEmbeddingService.shared.embedding(for: firstObs, in: cgImage) {
                    let sim = FaceEmbeddingService.shared.cosineSimilarity(firstResult.embedding, userEmb)
                    if sim >= FaceEmbeddingService.matchThreshold {
                        continue // Skip: this is just the user's face
                    }
                }
            }

            for obs in observations {
                guard let result = await FaceEmbeddingService.shared.embedding(
                    for: obs, in: cgImage
                ) else { continue }

                // Check face appearance limit
                // Single-face photos: max 3 per person
                // Multi-face photos: max 6 per person (more lenient since other faces add value)
                let clusterIdx = findOrCreateCluster(result.embedding, clusters: &faceClusters, counts: &faceAppearanceCounts, sums: &faceClusterSums)
                let limit = hasMultipleFaces ? Self.maxFaceAppearances * 2 : Self.maxFaceAppearances
                if faceAppearanceCounts[clusterIdx] >= limit {
                    continue
                }
                faceAppearanceCounts[clusterIdx] += 1

                // Check if this face matches any chapter partner.
                // suggestThreshold (0.35) is intentionally looser than the strict identity
                // matchThreshold (0.45) — false matches in the feed are recoverable because
                // the user gets to confirm before any photo is added to a chapter.
                let feedMatchThreshold: Float = FaceEmbeddingService.suggestThreshold
                var bestMatch: (chapterID: String, partnerName: String, similarity: Float)?
                for partner in partnerEmbeddings {
                    let sim = FaceEmbeddingService.shared.cosineSimilarity(
                        result.embedding, partner.embedding
                    )
                    if sim >= feedMatchThreshold {
                        if bestMatch == nil || sim > bestMatch!.similarity {
                            bestMatch = (partner.chapterID, partner.partnerName, sim)
                        }
                    }
                }

                if let match = bestMatch {
                    if (newFaceCards.count + unsavedMemoryCards.count) < maxCards {
                        let depth = assetDepth[asset.localIdentifier] ?? i
                        unsavedMemoryCards.append(FeedCard(
                            type: .unsavedMemory,
                            asset: asset,
                            faceCrop: result.crop,
                            faceObservation: obs,
                            embedding: result.embedding,
                            matchedChapterID: match.chapterID,
                            matchedPartnerName: match.partnerName,
                            photoDepth: depth
                        ))
                    }
                } else {
                    // New face: no chapter for this person
                    if (newFaceCards.count + unsavedMemoryCards.count) < maxCards {
                        let depth = assetDepth[asset.localIdentifier] ?? i
                        newFaceCards.append(FeedCard(
                            type: .newFace,
                            asset: asset,
                            faceCrop: result.crop,
                            faceObservation: obs,
                            embedding: result.embedding,
                            matchedChapterID: nil,
                            matchedPartnerName: nil,
                            photoDepth: depth
                        ))
                    }
                }

                break // One face per photo for the feed
            }
        }

        // Interleave 1:1
        var feed: [FeedCard] = []
        let count = max(newFaceCards.count, unsavedMemoryCards.count)
        for i in 0 ..< count {
            if i < newFaceCards.count { feed.append(newFaceCards[i]) }
            if i < unsavedMemoryCards.count { feed.append(unsavedMemoryCards[i]) }
        }

        logger.info("Feed built: \(newFaceCards.count) new faces, \(unsavedMemoryCards.count) unsaved memories")
        return feed
    }

    /// Dedup threshold — when grouping multiple feed cards of the same person.
    /// Errs on the side of "same" to avoid showing 5 cards of the same face.
    /// Slightly looser than suggestThreshold so cross-angle/lighting variations dedup correctly.
    private static let dedupThreshold: Float = 0.30

    /// Find which cluster this embedding belongs to, or create a new one.
    /// Uses centroid averaging for stability (same as PhotoLibraryScanner).
    private func findOrCreateCluster(
        _ embedding: [Float],
        clusters: inout [[Float]],
        counts: inout [Int],
        sums: inout [[Float]]
    ) -> Int {
        var bestIdx: Int?
        var bestSim: Float = -1
        for (i, centroid) in clusters.enumerated() {
            let sim = FaceEmbeddingService.shared.cosineSimilarity(embedding, centroid)
            if sim > bestSim { bestSim = sim; bestIdx = i }
        }
        if let idx = bestIdx, bestSim >= Self.dedupThreshold {
            // Update centroid (running average, L2-normalized)
            for k in 0 ..< sums[idx].count { sums[idx][k] += embedding[k] }
            let n = Float(counts[idx] + 1)
            var avg = sums[idx].map { $0 / n }
            var norm: Float = 0
            for x in avg { norm += x * x }
            norm = norm.squareRoot()
            if norm > 0 { avg = avg.map { $0 / norm } }
            clusters[idx] = avg
            return idx
        }
        // New cluster
        clusters.append(embedding)
        counts.append(0)
        sums.append(embedding)
        return clusters.count - 1
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
