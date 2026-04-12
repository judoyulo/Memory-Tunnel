// ChapterFaceConfirmationView.swift
// Lets the user confirm which face belongs to the chapter's partner.
// Scans photos from the chapter, detects faces, shows them as bubbles.
// User taps the correct face → embedding is saved for that chapter/partner.
// This improves "Find photos" accuracy and feed card matching.

import SwiftUI

struct ChapterFaceConfirmationView: View {
    let chapter: Chapter
    let memories: [Memory]
    @State private var faces: [(crop: UIImage, embedding: [Float])] = []
    @State private var selectedIndex: Int?
    @State private var isScanning = true
    @State private var isSaving = false
    @State private var saved = false
    @State private var existingFaceCrop: UIImage?
    @Environment(\.dismiss) private var dismiss

    var partnerName: String {
        chapter.partner?.displayName ?? "them"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.lg) {
                Text(L.whichFace(partnerName))
                    .font(.mtTitle)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.lg)

                Text(L.helpsFindPhotos)
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)

                // Show existing linked face if any
                if let crop = existingFaceCrop {
                    VStack(spacing: 6) {
                        Text(L.currentFace)
                            .font(.mtCaption)
                            .foregroundStyle(Color.mtSecondary)
                        Image(uiImage: crop)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.mtAccent, lineWidth: 2))
                    }
                }

                if isScanning {
                    Spacer()
                    ProgressView()
                    Text(L.scanningMemoryLanePhotos)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                } else if faces.isEmpty {
                    Spacer()
                    Image(systemName: "face.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.mtTertiary)
                    Text(L.noFacesInPhotos)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                } else if saved {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.mtAccent)
                    Text(L.faceSaved(partnerName))
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                    Text(L.appWillRecognize)
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                } else {
                    // Face bubbles
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.lg) {
                            ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                                Button { selectedIndex = index } label: {
                                    Image(uiImage: face.crop)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(
                                                selectedIndex == index ? Color.mtLabel : Color.clear,
                                                lineWidth: 3
                                            )
                                        )
                                        .shadow(color: selectedIndex == index ? Color.mtLabel.opacity(0.3) : .clear, radius: 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                    }

                    Spacer()
                }

                // Confirm button
                if !faces.isEmpty && !saved {
                    Button {
                        Task { await confirmFace() }
                    } label: {
                        Text(isSaving ? "Saving..." : "Confirm")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedIndex != nil ? Color.mtLabel : Color.mtTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .disabled(selectedIndex == nil || isSaving)
                    .padding(.horizontal, Spacing.xl)
                }

                if saved {
                    Button(L.done) { dismiss() }
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .padding(.bottom, Spacing.md)
                }
            }
            .padding(.bottom, Spacing.lg)
            .background(Color.mtBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.cancel) { dismiss() }
                }
            }
            .task {
                // Load existing linked face crop
                let partnerID = chapter.partner?.id ?? chapter.id
                var record = await FaceEmbeddingService.shared.faceRecordForChapter(chapterID: chapter.id)
                if record == nil {
                    record = await FaceEmbeddingService.shared.faceRecordForPartner(partnerID: partnerID)
                }
                if let jpegData = record?.cropJPEG {
                    existingFaceCrop = UIImage(data: jpegData)
                }

                await scanChapterPhotos()
            }
        }
    }

    private func scanChapterPhotos() async {
        isScanning = true
        defer { isScanning = false }

        // Collect unique faces from chapter photos
        var allFaces: [(crop: UIImage, embedding: [Float])] = []
        var faceClusters: [[Float]] = []

        let photoMemories = memories.filter { $0.mediaType == "photo" && $0.mediaURL != nil }

        for memory in photoMemories.prefix(10) {
            guard let url = memory.mediaURL,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else { continue }

            let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
            for obs in observations {
                guard let result = await FaceEmbeddingService.shared.embedding(for: obs, in: cgImage) else { continue }

                // Deduplicate: skip if too similar to existing face
                var isDuplicate = false
                for cluster in faceClusters {
                    let sim = FaceEmbeddingService.shared.cosineSimilarity(result.embedding, cluster)
                    if sim >= FaceEmbeddingService.matchThreshold {
                        isDuplicate = true
                        break
                    }
                }

                if !isDuplicate {
                    allFaces.append((crop: result.crop, embedding: result.embedding))
                    faceClusters.append(result.embedding)
                }
            }

            if allFaces.count >= 8 { break }
        }

        faces = allFaces
    }

    private func confirmFace() async {
        guard let index = selectedIndex, index < faces.count else { return }

        isSaving = true
        let face = faces[index]
        let partnerID = chapter.partner?.id ?? chapter.id

        await FaceEmbeddingService.shared.linkFaceToChapter(
            embedding: face.embedding,
            crop: face.crop,
            partnerID: partnerID,
            chapterID: chapter.id
        )

        withAnimation { saved = true }
        isSaving = false
    }
}
