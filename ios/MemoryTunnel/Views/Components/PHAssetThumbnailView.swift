import SwiftUI
import Photos

/// Loads and displays a thumbnail for a PHAsset. Detects iCloud-only assets.
/// Shared component used by FaceBubblesView, ChapterCreationView, and legacy SmartStartView.
struct PHAssetThumbnailView: View {
    let asset: PHAsset
    let onCloudDetected: (() -> Void)?
    @State private var thumbnail: UIImage?

    init(asset: PHAsset, onCloudDetected: (() -> Void)? = nil) {
        self.asset = asset
        self.onCloudDetected = onCloudDetected
    }

    var body: some View {
        ZStack {
            Color.mtSurface
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Color.mtSecondary.opacity(0.4))
            }
        }
        .clipped()
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let size = CGSize(width: 200, height: 200)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        // Use opportunistic delivery: accepts the first usable result (degraded or not).
        // This prevents continuation hangs with fastFormat on some devices.
        thumbnail = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if isInCloud {
                    resumed = true
                    Task { @MainActor in self.onCloudDetected?() }
                    continuation.resume(returning: nil)
                    return
                }
                // Accept any non-nil image (degraded or final)
                if image != nil {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

/// Loads a full-quality image from a PHAsset. Returns nil for iCloud-only assets.
func loadFullImage(for asset: PHAsset) async -> UIImage? {
    await withCheckedContinuation { continuation in
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        var resumed = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1200, height: 1200),
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
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                resumed = true
                continuation.resume(returning: image)
            }
            // highQualityFormat guarantees a non-degraded callback for local photos.
            // iCloud photos are caught by the isInCloud guard above.
        }
    }
}
