import SwiftUI
import Photos
import PhotosUI

/// Multi-step chapter creation flow.
/// Entered from face bubble tap (with suggestion) or manual creation (nil suggestion).
struct ChapterCreationView: View {
    @StateObject private var vm: ChapterCreationViewModel
    let onComplete: (String?) -> Void  // chapterID if created, nil if cancelled
    let onCreateAnother: (() -> Void)? // batch creation: return to bubbles

    init(suggestion: FaceSuggestion?, onComplete: @escaping (String?) -> Void, onCreateAnother: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: ChapterCreationViewModel(suggestion: suggestion))
        self.onComplete = onComplete
        self.onCreateAnother = onCreateAnother
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                switch vm.step {
                case .selectPhotos:
                    selectPhotosScreen
                case .nameChapter:
                    nameChapterScreen
                case .addContent:
                    addContentScreen
                case .batchReview(let chapterID):
                    BatchPhotoReviewView(
                        chapterID: chapterID,
                        initialImages: vm.selectedPhotos.map { (image: $0.image, takenAt: $0.asset.creationDate) },
                        embedded: true
                    ) {
                        // After batch upload completes, go to complete screen
                        Task {
                            let shareURL = await createInvitation(chapterID: chapterID)
                            UserDefaults.standard.set(true, forKey: "smartStartCompleted")
                            vm.step = .complete(chapterID: chapterID, shareURL: shareURL)
                        }
                    }
                case .uploading:
                    uploadingScreen
                case .complete(let chapterID, let shareURL):
                    completeScreen(chapterID: chapterID, shareURL: shareURL)
                case .viewingChapter(let chapterID):
                    ChapterDetailView(chapter: Chapter(id: chapterID, status: "active", name: vm.personName))
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L.back) {
                                    // Return to face bubbles
                                    if let onCreateAnother {
                                        onCreateAnother()
                                    } else {
                                        onComplete(chapterID)
                                    }
                                }
                            }
                        }
                }
            }
            .animation(.mtSlide, value: vm.step)
        }
    }

    // MARK: - Select Photos

    @ViewBuilder
    private var selectPhotosScreen: some View {
        VStack(spacing: 0) {
            // Header
            Text(L.choosePhotos)
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)

            if !vm.selectedPhotos.isEmpty {
                Text(L.selected(vm.selectedPhotos.count))
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
                    .padding(.bottom, Spacing.sm)
            }

            // Photo grid
            if let suggestion = vm.suggestion {
                // From face bubble: show face's photos
                ScrollView {
                    let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(suggestion.recentAssets, id: \.localIdentifier) { asset in
                            PhotoSelectableTile(
                                asset: asset,
                                isSelected: vm.selectedPhotos.contains { $0.asset.localIdentifier == asset.localIdentifier }
                            ) { image in
                                vm.selectPhoto(asset: asset, image: image)
                            }
                        }
                    }
                }
            } else {
                // Manual: system photo picker
                ManualPhotoPickerSection(vm: vm)
            }

            // Selected photos strip
            if !vm.selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(vm.selectedPhotos, id: \.asset.localIdentifier) { photo in
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .frame(height: 64)
                .padding(.vertical, Spacing.sm)
            }

            // Continue button
            PrimaryButton(title: L.continueBtn, isLoading: false) {
                vm.proceedToName()
            }
            .disabled(vm.selectedPhotos.isEmpty)
            .opacity(vm.selectedPhotos.isEmpty ? 0.4 : 1)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .navigationTitle(vm.suggestion != nil ? L.photosWithName(vm.suggestion?.name ?? "") : L.choosePhotos)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L.cancel) { onComplete(nil) }
                    .foregroundStyle(Color.mtSecondary)
            }
        }
    }

    // MARK: - Name Chapter

    @ViewBuilder
    private var nameChapterScreen: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Face crop if from suggestion
            if let crop = vm.suggestion?.sampleCrop {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            }

            Text(L.nameThisMemoryLane)
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            VStack(spacing: Spacing.md) {
                TextField(L.theirName, text: $vm.personName)
                    .font(.mtBody)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                TextField(L.chapterNameOptional, text: $vm.chapterName)
                    .font(.mtBody)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()

            PrimaryButton(title: L.continueBtn, isLoading: false) {
                vm.proceedToContent()
            }
            .disabled(vm.personName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(vm.personName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Add Content (single photo or chooser for multi)

    @ViewBuilder
    private var addContentScreen: some View {
        if vm.selectedPhotos.count > 1 {
            // Multiple photos: offer "add details to each" or "add directly"
            multiPhotoChooser
        } else {
            singlePhotoContent
        }
    }

    private var multiPhotoChooser: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Photo strip preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(vm.selectedPhotos.enumerated()), id: \.offset) { _, photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, Spacing.md)
            }

            Text(L.photosSelected(vm.selectedPhotos.count))
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)

            Spacer()

            VStack(spacing: Spacing.sm) {
                // Add details to each → open BatchPhotoReviewView after chapter creation
                Button {
                    vm.detailMode = .perPhoto
                    vm.startUpload()
                } label: {
                    Label(L.addDetailsToEach, systemImage: "pencil")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                Button {
                    vm.detailMode = .direct
                    vm.startUpload()
                } label: {
                    Text(L.addAllDirectly)
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
        .navigationTitle(L.addDetails)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var singlePhotoContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let first = vm.selectedPhotos.first {
                    Image(uiImage: first.image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    TextField(L.captionOptional, text: $vm.caption, axis: .vertical)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtLabel)
                        .lineLimit(3)
                        .padding(Spacing.md)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                    HStack {
                        Image(systemName: "mappin")
                            .foregroundStyle(Color.mtSecondary)
                        TextField(L.addALocation, text: $vm.locationName)
                            .font(.mtBody)
                    }
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.mtSecondary)
                        if let date = vm.takenAt {
                            Text(date, style: .date)
                                .font(.mtBody)
                                .foregroundStyle(Color.mtLabel)
                        } else {
                            Text(L.addADate)
                                .font(.mtBody)
                                .foregroundStyle(Color.mtTertiary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.mtCaption)
                            .foregroundStyle(Color.mtError)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                PrimaryButton(title: L.createMemoryLane, isLoading: vm.isLoading) {
                    vm.detailMode = .direct
                    vm.startUpload()
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
            }
        }
        .navigationTitle(L.addDetails)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Uploading

    @ViewBuilder
    private var uploadingScreen: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
            Text(vm.uploadProgress.isEmpty ? L.creatingYourMemoryLane : vm.uploadProgress)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }

    // MARK: - Complete

    @ViewBuilder
    private func completeScreen(chapterID: String, shareURL: URL?) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Amber checkmark — emotional peak
            ZStack {
                Circle()
                    .fill(Color.mtAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.mtAccent)
            }

            Text(L.chapterCreated())
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text(L.readyToInvite(vm.personName))
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)

            Spacer()

            VStack(spacing: Spacing.md) {
                // View the memory lane inline, back button returns to bubbles
                Button {
                    vm.step = .viewingChapter(chapterID: chapterID)
                } label: {
                    Label(L.viewInMemoryLane, systemImage: "book.fill")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                if let url = shareURL {
                    ShareLink(item: url) {
                        Text(L.invite(vm.personName))
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

                if let onCreateAnother {
                    Button(L.createAnotherMemoryLane) {
                        onCreateAnother()
                    }
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
                }

                Button(L.done) {
                    onComplete(chapterID)
                }
                .font(.mtCaption)
                .foregroundStyle(Color.mtTertiary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Helpers

    private func createInvitation(chapterID: String) async -> URL? {
        guard let firstMemory = try? await APIClient.shared.memories(chapterID: chapterID).first,
              let invitation = try? await APIClient.shared.createInvitation(
                  chapterID: chapterID, memoryID: firstMemory.id
              ) else { return nil }
        return invitation.shareURL
    }
}

// MARK: - Manual Photo Picker

private struct ManualPhotoPickerSection: View {
    @ObservedObject var vm: ChapterCreationViewModel
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if vm.selectedPhotos.isEmpty {
                Spacer()
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.mtTertiary)
                        Text(L.tapToChoosePhotos)
                            .font(.mtBody)
                            .foregroundStyle(Color.mtSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxl)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                }
                Spacer()
            } else {
                // Show selected photos in a grid
                ScrollView {
                    let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(vm.selectedPhotos, id: \.asset.localIdentifier) { photo in
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(minHeight: 100)
                                .clipped()
                        }
                    }
                }

                // Add more photos
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    Text(L.addMorePhotos)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }
            }
        }
        .onChange(of: selectedItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        // Create a dummy PHAsset reference for manual picks
                        // In manual mode, we don't have PHAsset — store image directly
                        vm.addManualPhoto(image: image)
                    }
                }
                selectedItems = []
            }
        }
    }
}

// MARK: - Photo Selectable Tile

private struct PhotoSelectableTile: View {
    let asset: PHAsset
    let isSelected: Bool
    let onSelect: (UIImage) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PHAssetThumbnailView(asset: asset)
                .aspectRatio(1, contentMode: .fit)

            if isSelected {
                ZStack {
                    Circle()
                        .fill(Color.mtLabel)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.mtBackground)
                }
                .padding(4)
            }
        }
        .onTapGesture {
            Task {
                if let image = await loadFullImage(for: asset) {
                    onSelect(image)
                }
            }
        }
    }
}
