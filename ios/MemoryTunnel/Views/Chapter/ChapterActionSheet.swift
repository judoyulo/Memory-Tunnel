// ChapterActionSheet.swift
// Shown after creating a chapter or adding photos to one.
// Four actions: scan more, manual add, go to chapter, back to cards.

import SwiftUI

struct ChapterActionSheet: View {
    let chapterID: String
    let chapterName: String
    let message: String
    let faceEmbedding: [Float]?
    let onGoToChapter: () -> Void  // Caller handles tab switching
    let onDismiss: () -> Void      // Dismiss all sheets
    @State private var showSuggestedPhotos = false
    @State private var showSendFlow = false

    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.lg) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.mtAccent)

                Text(message)
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)

                Text(chapterName)
                    .font(.mtTitle)
                    .foregroundStyle(Color.mtSecondary)

                Spacer()

                VStack(spacing: Spacing.sm) {
                    if faceEmbedding != nil {
                        Button { showSuggestedPhotos = true } label: {
                            Label("Find more photos by scanning", systemImage: "sparkle.magnifyingglass")
                                .font(.mtButton)
                                .foregroundStyle(Color.mtBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.mtLabel)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        }
                    }

                    Button { showSendFlow = true } label: {
                        Label("Add photos manually", systemImage: "photo.on.rectangle")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.mtLabel, lineWidth: 1.5)
                            )
                    }

                    Button { onGoToChapter() } label: {
                        Label("Go to chapter", systemImage: "book.fill")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.mtLabel, lineWidth: 1.5)
                            )
                    }

                    Button { onDismiss() } label: {
                        Text("Back to cards")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtSecondary)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.mtBackground)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSuggestedPhotos) {
                SuggestedPhotosView(
                    chapterID: chapterID,
                    partnerName: chapterName,
                    directEmbedding: faceEmbedding
                ) { _ in showSuggestedPhotos = false }
            }
            .sheet(isPresented: $showSendFlow) {
                SendFlowView(chapterID: chapterID)
            }
        }
    }
}
