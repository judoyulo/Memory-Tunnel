// ChapterPickerSheet.swift
// Shows added chapters as face bubble buttons. Tap to navigate to that chapter.

import SwiftUI

struct ChapterPickerSheet: View {
    let chapters: [(chapterID: String, partnerName: String)]
    @State private var faceCrops: [String: UIImage] = [:] // chapterID → face crop
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.lg) {
                Text("Which chapter?")
                    .font(.mtTitle)
                    .foregroundStyle(Color.mtLabel)
                    .padding(.top, Spacing.xl)

                if chapters.isEmpty {
                    Spacer()
                    Text("No chapters linked yet")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                                Button {
                                    let chID = chapter.chapterID
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        NotificationRouter.shared.pendingChapterID = chID
                                    }
                                } label: {
                                    HStack(spacing: Spacing.md) {
                                        // Face crop or initial
                                        if let crop = faceCrops[chapter.chapterID] {
                                            Image(uiImage: crop)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 56, height: 56)
                                                .clipShape(Circle())
                                        } else {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.mtSurface)
                                                    .frame(width: 56, height: 56)
                                                Text(String(chapter.partnerName.prefix(1).uppercased()))
                                                    .font(.mtTitle)
                                                    .foregroundStyle(Color.mtLabel)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(chapter.partnerName)
                                                .font(.mtLabel)
                                                .foregroundStyle(Color.mtLabel)
                                            Text("View in chapter")
                                                .font(.mtCaption)
                                                .foregroundStyle(Color.mtSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.mtTertiary)
                                    }
                                    .padding(Spacing.md)
                                    .background(Color.mtSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }

                Spacer()
            }
            .background(Color.mtBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadFaceCrops() }
        }
    }

    private func loadFaceCrops() async {
        for chapter in chapters {
            let partnerID = chapter.chapterID // Try both
            if let record = await FaceEmbeddingService.shared.faceRecordForChapter(chapterID: chapter.chapterID),
               let data = record.cropJPEG,
               let img = UIImage(data: data) {
                faceCrops[chapter.chapterID] = img
            } else if let record = await FaceEmbeddingService.shared.faceRecordForPartner(partnerID: partnerID),
                      let data = record.cropJPEG,
                      let img = UIImage(data: data) {
                faceCrops[chapter.chapterID] = img
            }
        }
    }
}
