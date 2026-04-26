import SwiftUI
import Photos
import CoreLocation

/// ViewModel for the multi-step chapter creation flow.
/// Handles photo selection, naming, content tagging, multi-photo upload, and invitations.
@MainActor
final class ChapterCreationViewModel: ObservableObject {
    enum Step: Equatable {
        case selectPhotos
        case nameChapter
        case addContent
        case batchReview(chapterID: String)
        case uploading
        case complete(chapterID: String, shareURL: URL?)
        case viewingChapter(chapterID: String)

        static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.selectPhotos, .selectPhotos),
                 (.nameChapter, .nameChapter),
                 (.addContent, .addContent),
                 (.uploading, .uploading): return true
            case (.batchReview(let a), .batchReview(let b)): return a == b
            case (.complete(let a, _), .complete(let b, _)): return a == b
            case (.viewingChapter(let a), .viewingChapter(let b)): return a == b
            default: return false
            }
        }
    }

    enum DetailMode { case direct, perPhoto }

    @Published var step: Step = .selectPhotos
    @Published var detailMode: DetailMode = .direct
    @Published var selectedPhotos: [(asset: PHAsset, image: UIImage)] = []
    @Published var personName: String = ""
    @Published var chapterName: String = ""
    @Published var caption: String = ""
    @Published var locationName: String = ""
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var takenAt: Date?
    @Published var uploadProgress: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    // Face suggestion (nil = manual mode)
    let suggestion: FaceSuggestion?
    private var createdChapterID: String?
    private var uploadedPhotoIndices: Set<Int> = []  // Track which photos already uploaded

    init(suggestion: FaceSuggestion?) {
        self.suggestion = suggestion
        if let s = suggestion {
            self.personName = s.name
        }
    }

    // MARK: - Photo Selection

    func selectPhoto(asset: PHAsset, image: UIImage) {
        if selectedPhotos.contains(where: { $0.asset.localIdentifier == asset.localIdentifier }) {
            selectedPhotos.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
        } else {
            selectedPhotos.append((asset, image))
        }

        // Auto-extract EXIF from first selected photo
        if selectedPhotos.count == 1 {
            extractEXIF(from: asset)
        }
    }

    /// Add a photo from the manual PhotosPicker (no PHAsset available).
    func addManualPhoto(image: UIImage) {
        // Use a placeholder PHAsset — manual photos don't have EXIF from PHAsset
        // We store the image directly; the upload pipeline uses the UIImage, not the asset.
        let placeholder = PHAsset()
        selectedPhotos.append((asset: placeholder, image: image))
    }

    func proceedToName() {
        guard !selectedPhotos.isEmpty else { return }
        step = .nameChapter
    }

    func proceedToContent() {
        guard !personName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if chapterName.trimmingCharacters(in: .whitespaces).isEmpty {
            chapterName = personName
        }
        step = .addContent
    }

    func startUpload() {
        Task { await upload() }
    }

    // MARK: - Reverse Geocode

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                guard let place = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                var parts: [String] = []
                if let city = place.locality { parts.append(city) }
                if let country = place.country { parts.append(country) }
                continuation.resume(returning: parts.isEmpty ? nil : parts.joined(separator: ", "))
            }
        }
    }

    // MARK: - EXIF Extraction

    private func extractEXIF(from asset: PHAsset) {
        // Date from EXIF
        if let date = asset.creationDate {
            takenAt = date
        }

        // Location from EXIF
        if let location = asset.location {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude

            // Reverse geocode
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                guard let place = placemarks?.first else { return }
                Task { @MainActor in
                    var parts: [String] = []
                    if let city = place.locality { parts.append(city) }
                    if let country = place.country { parts.append(country) }
                    if !parts.isEmpty {
                        self?.locationName = parts.joined(separator: ", ")
                    }
                }
            }
        }
    }

    // MARK: - Upload Pipeline

    private func upload() async {
        step = .uploading
        isLoading = true
        errorMessage = nil

        do {
            // 1. Create chapter (once)
            if createdChapterID == nil {
                let name = chapterName.trimmingCharacters(in: .whitespaces)
                let chapter = try await APIClient.shared.createChapter(name: name.isEmpty ? nil : name)
                createdChapterID = chapter.id

                // Pin the bubble's face embedding to this chapter so future face matching
                // recognizes THIS specific person, not whichever face appears first in
                // an uploaded photo with multiple people.
                if let suggestion {
                    let partnerID = chapter.partner?.id ?? chapter.id
                    await FaceEmbeddingService.shared.linkFaceToChapter(
                        embedding: suggestion.embedding,
                        crop: suggestion.sampleCrop,
                        partnerID: partnerID,
                        chapterID: chapter.id
                    )
                }
            }

            guard let chapterID = createdChapterID else { return }

            // If perPhoto mode, hand off to BatchPhotoReviewView
            if detailMode == .perPhoto {
                isLoading = false
                step = .batchReview(chapterID: chapterID)
                return
            }

            // 2. Upload each photo sequentially (skip already-uploaded on retry)
            var shareURL: URL?
            let total = selectedPhotos.count
            for (i, photo) in selectedPhotos.enumerated() {
                if uploadedPhotoIndices.contains(i) { continue }

                let remaining = total - uploadedPhotoIndices.count
                let current = total - remaining + 1
                uploadProgress = L.uploading(current, total)

                guard let data = photo.image.jpegData(compressionQuality: 0.85) else { continue }

                // Per-photo EXIF: use the photo's own asset location/date if available
                let photoDate = photo.asset.creationDate ?? takenAt
                var photoLat = latitude
                var photoLng = longitude
                var photoLoc = locationName.isEmpty ? nil : locationName
                if let loc = photo.asset.location {
                    photoLat = loc.coordinate.latitude
                    photoLng = loc.coordinate.longitude
                    // Reverse geocode synchronously from cache if available
                    if photoLoc == nil || i > 0 {
                        photoLoc = await reverseGeocode(loc)
                    }
                }

                let presign = try await APIClient.shared.presign(chapterID: chapterID)
                try await APIClient.shared.uploadToS3(data: data, presign: presign)
                _ = try await APIClient.shared.createMemory(
                    chapterID: chapterID,
                    s3Key: presign.s3Key,
                    caption: uploadedPhotoIndices.isEmpty ? (caption.isEmpty ? nil : caption) : nil,
                    takenAt: photoDate,
                    visibility: "this_item",
                    locationName: photoLoc,
                    latitude: photoLat,
                    longitude: photoLng
                )
                uploadedPhotoIndices.insert(i)
            }

            // 3. Create invitation (non-fatal)
            if let firstMemory = try? await APIClient.shared.memories(chapterID: chapterID).first {
                if let invitation = try? await APIClient.shared.createInvitation(
                    chapterID: chapterID, memoryID: firstMemory.id
                ) {
                    shareURL = invitation.shareURL
                }
            }

            UserDefaults.standard.set(true, forKey: "smartStartCompleted")
            step = .complete(chapterID: chapterID, shareURL: shareURL)

        } catch {
            uploadProgress = ""
            errorMessage = "Upload failed. \(uploadedPhotoIndices.count) of \(selectedPhotos.count) photos saved. Tap to retry."
            step = .addContent
        }

        isLoading = false
    }
}
