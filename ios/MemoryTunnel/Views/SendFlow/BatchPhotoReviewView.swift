// BatchPhotoReviewView.swift
// After selecting multiple photos, asks user:
// "Add details to each photo?" or "Add all directly".

import SwiftUI
import Photos

struct BatchPhotoReviewView: View {
    let chapterID: String
    var initialImages: [(image: UIImage, takenAt: Date?)]
    var embedded: Bool = false
    var faceEmbedding: [Float]? = nil  // For "Find more photos" scanning
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum Mode { case choosing, scanning, editing, uploading, done }

    @State private var mode: Mode = .choosing
    @State private var allImages: [(image: UIImage, takenAt: Date?)] = []
    @State private var currentIndex = 0
    @State private var captions: [String] = []
    @State private var locations: [String] = []
    @State private var eventDates: [Date?] = []
    @State private var emotionTags: [Set<String>] = []
    @State private var uploadedCount = 0
    @State private var totalToUpload = 0

    var body: some View {
        let content = ZStack {
            Color.mtBackground.ignoresSafeArea()

            switch mode {
            case .choosing:  choosingView
            case .scanning:  scanningView
            case .editing:   editingView
            case .uploading: uploadingView
            case .done:      doneView
            }
        }
        .onAppear {
            allImages = initialImages
            resetMetadata()
        }

        if embedded {
            content
        } else {
            NavigationView {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if mode == .choosing || mode == .editing {
                                Button("Cancel") { dismiss() }
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Choose

    private var choosingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            if !allImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(allImages.enumerated()), id: \.offset) { i, item in
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }

            Text("\(allImages.count) photo\(allImages.count == 1 ? "" : "s") selected")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            Spacer()

            VStack(spacing: Spacing.sm) {
                // Find more photos by scanning
                if faceEmbedding != nil {
                    Button { mode = .scanning } label: {
                        Label("Find more photos of this person", systemImage: "sparkle.magnifyingglass")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Color.mtLabel, lineWidth: 1.5))
                    }
                }

                Button { mode = .editing } label: {
                    Label("Add details to each photo", systemImage: "pencil")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                Button { startUpload() } label: {
                    Text("Add all directly")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Edit

    @ViewBuilder
    private var editingView: some View {
        if allImages.isEmpty {
            Text("No photos")
        } else {
            let safeIndex = min(currentIndex, allImages.count - 1)
            VStack(spacing: 0) {

            Text("Photo \(safeIndex + 1) of \(allImages.count)")
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .padding(.top, Spacing.sm)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    Image(uiImage: allImages[safeIndex].image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                    if safeIndex < captions.count {
                        TextField("Add a caption (optional)", text: $captions[safeIndex])
                            .font(.mtBody)
                            .padding(12)
                            .background(Color.mtSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }

                    if safeIndex < locations.count && safeIndex < emotionTags.count {
                        MemoryMetadataFields(
                            locationName: $locations[safeIndex],
                            eventDate: $eventDates[safeIndex],
                            emotionTags: $emotionTags[safeIndex]
                        )
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }


            HStack(spacing: Spacing.md) {
                if safeIndex > 0 {
                    Button { currentIndex -= 1 } label: {
                        Text("Previous")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.mtLabel, lineWidth: 1.5)
                            )
                    }
                }

                Button {
                    if safeIndex < allImages.count - 1 {
                        currentIndex += 1
                    } else {
                        startUpload()
                    }
                } label: {
                    Text(safeIndex < allImages.count - 1 ? "Next" : "Add all")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
            }
        }
    }

    // MARK: - Uploading

    private var uploadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
            Text("Uploading \(uploadedCount)/\(totalToUpload)...")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.mtAccent)
            Text("\(uploadedCount) photo\(uploadedCount == 1 ? "" : "s") added")
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)
            Spacer()
            Button {
                onDone()
                dismiss()
            } label: {
                Text("Done")
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Upload

    private func startUpload() {
        guard !chapterID.isEmpty else { return }
        mode = .uploading
        totalToUpload = allImages.count
        uploadedCount = 0

        Task { @MainActor in
            for (i, item) in allImages.enumerated() {
                guard let jpeg = item.image.jpegData(compressionQuality: 0.85) else { continue }
                do {
                    let presign = try await APIClient.shared.presign(chapterID: chapterID)
                    try await APIClient.shared.uploadToS3(data: jpeg, presign: presign)
                    let caption = i < captions.count && !captions[i].isEmpty ? captions[i] : nil
                    let location = i < locations.count && !locations[i].isEmpty ? locations[i] : nil
                    let takenAt = i < eventDates.count ? eventDates[i] : item.takenAt
                    let tags = i < emotionTags.count && !emotionTags[i].isEmpty ? Array(emotionTags[i]) : nil
                    _ = try await APIClient.shared.createMemory(
                        chapterID: chapterID,
                        s3Key: presign.s3Key,
                        caption: caption,
                        takenAt: takenAt,
                        visibility: "this_item",
                        locationName: location,
                        width: Int(item.image.size.width),
                        height: Int(item.image.size.height)
                    )
                    uploadedCount += 1
                    Task { await FaceEmbeddingService.shared.processFaces(in: item.image) }
                } catch {
                    print("[BatchUpload] failed: \(error)")
                }
            }
            if embedded {
                onDone()
            } else {
                mode = .done
            }
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        SuggestedPhotosView(
            chapterID: chapterID,
            partnerName: "this person",
            directEmbedding: faceEmbedding
        ) { selectedAssets in
            // Load selected photos and add to allImages
            Task {
                for asset in selectedAssets {
                    if let img = await loadFullImage(for: asset) {
                        allImages.append((image: img, takenAt: asset.creationDate))
                    }
                }
                resetMetadata()
                mode = .choosing
            }
        }
    }

    private func resetMetadata() {
        captions = Array(repeating: "", count: allImages.count)
        locations = Array(repeating: "", count: allImages.count)
        eventDates = allImages.map { $0.takenAt }
        emotionTags = Array(repeating: Set<String>(), count: allImages.count)
        currentIndex = 0
    }

    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit, options: options
            ) { img, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded { resumed = true; continuation.resume(returning: img) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }
}

