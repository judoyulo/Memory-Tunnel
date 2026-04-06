// ReconnectionService.swift
// Computes decay scores for face clusters and selects reconnection candidates.
// A reconnection candidate is someone you have photos with but haven't interacted
// with recently — the person you should reach out to.
//
// Decay formula: (days_since_last_photo / 365) * log2(total_photos + 1)
// Higher score = stronger reconnection signal.

import Photos
import UIKit
import os.log

private let logger = Logger(subsystem: "com.memorytunnel.app", category: "Reconnection")

// MARK: - ReconnectionCandidate

struct ReconnectionCandidate: Identifiable {
    let id: UUID
    let faceCrop: UIImage
    let bestPhoto: PHAsset
    let photoCount: Int
    let decayScore: Double
    let daysSinceLastPhoto: Int
    let oldestDate: Date?
    let newestDate: Date?
    var name: String

    var decayLabel: String {
        if decayScore > 15 { return "Lost touch" }
        if decayScore > 8  { return "Going cold" }
        if decayScore > 3  { return "Fading" }
        return "Recent"
    }
}

// MARK: - ReconnectionService

actor ReconnectionService {

    static let shared = ReconnectionService()
    private init() {}

    /// Minimum decay score to qualify as a reconnection candidate.
    static let decayThreshold: Double = 5.0

    /// Scan the photo library and return reconnection candidates sorted by decay score.
    /// This runs the full face clustering pipeline and computes decay for each cluster.
    func findCandidates() async -> [ReconnectionCandidate] {
        let scanStart = Date()

        // Run face scan
        var latestSuggestions: [FaceSuggestion] = []
        let stream = await PhotoLibraryScanner.shared.scanFacesProgressively()
        for await snapshot in stream {
            latestSuggestions = snapshot
        }

        guard !latestSuggestions.isEmpty else {
            logger.info("No face clusters found")
            return []
        }

        // Compute decay scores and select best photo per cluster
        let now = Date()
        var candidates: [ReconnectionCandidate] = []

        for suggestion in latestSuggestions {
            let dates = suggestion.recentAssets.compactMap(\.creationDate)
            guard !dates.isEmpty else { continue }

            let oldest = dates.min()
            let newest = dates.max()!
            let daysSince = Calendar.current.dateComponents([.day], from: newest, to: now).day ?? 0
            let decayScore = (Double(daysSince) / 365.0) * log2(Double(suggestion.count) + 1)

            guard decayScore >= Self.decayThreshold else { continue }

            // Select best photo: isFavorite > highest resolution > most recent
            let bestAsset = selectBestPhoto(from: suggestion.recentAssets)

            candidates.append(ReconnectionCandidate(
                id: suggestion.id,
                faceCrop: suggestion.sampleCrop,
                bestPhoto: bestAsset,
                photoCount: suggestion.count,
                decayScore: decayScore,
                daysSinceLastPhoto: daysSince,
                oldestDate: oldest,
                newestDate: newest,
                name: suggestion.name
            ))
        }

        // Sort by decay score (highest = most disconnected)
        candidates.sort { $0.decayScore > $1.decayScore }

        let elapsed = Date().timeIntervalSince(scanStart)
        logger.info("Found \(candidates.count) reconnection candidates from \(latestSuggestions.count) clusters in \(String(format: "%.1f", elapsed))s")

        return candidates
    }

    /// Select the best photo from a set of assets.
    /// Priority: isFavorite > highest resolution > most recent.
    private func selectBestPhoto(from assets: [PHAsset]) -> PHAsset {
        // Check for favorites first
        let favorites = assets.filter(\.isFavorite)
        if let fav = favorites.max(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) {
            return fav
        }

        // No favorites: pick highest resolution from the most recent 20% (min 3)
        let sorted = assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        let recentCount = max(3, sorted.count / 5)
        let recentSlice = Array(sorted.prefix(recentCount))

        return recentSlice.max(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) ?? assets[0]
    }

    /// Load a full-quality UIImage from a PHAsset for display or sharing.
    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }
}
