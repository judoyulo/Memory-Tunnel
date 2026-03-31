// FaceTaggingBanner.swift
// Dismissable bottom-of-screen prompt that appears in ChapterDetailView when
// untagged face records exist for this chapter's partner.
//
// Design spec (DESIGN.md § Face Indexing UX):
//   - Never modal; always safeAreaInset at the bottom
//   - One face at a time — no grid of unknowns
//   - Primary: "Yes, that's [Name]" (Primary button variant)
//   - Ghost:   "Skip" (Ghost variant)
//   - Skipped faces are removed from the session queue; they resurface after 7 days

import SwiftUI

// MARK: - FaceTaggingBanner

struct FaceTaggingBanner: View {
    let face: FaceRecord
    let partnerName: String
    let onConfirm: () async -> Void
    let onSkip: () -> Void

    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                // Face crop thumbnail
                Group {
                    if let jpeg = face.cropJPEG, let ui = UIImage(data: jpeg) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.mtSurface
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.mtSecondary)
                            )
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                // Question
                VStack(alignment: .leading, spacing: 2) {
                    Text("Who's in this photo?")
                        .font(.mtLabel)
                        .foregroundStyle(Color.mtLabel)
                    Text("Helps Memory Tunnel remember them next time.")
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            HStack(spacing: Spacing.sm) {
                // Ghost: Skip
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button)
                                .stroke(Color.mtLabel, lineWidth: 1.5)
                        )
                }

                // Primary: confirm
                Button {
                    guard !isConfirming else { return }
                    isConfirming = true
                    Task {
                        await onConfirm()
                        isConfirming = false
                    }
                } label: {
                    ZStack {
                        Text("Yes, that's \(partnerName)")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtBackground)
                            .opacity(isConfirming ? 0 : 1)
                        if isConfirming {
                            ProgressView()
                                .tint(Color.mtBackground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .disabled(isConfirming)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: -2)
    }
}

// MARK: - ChapterDetailView + Face Tagging

/// View modifier that loads untagged faces for a chapter and surfaces the
/// FaceTaggingBanner as a safeAreaInset at the bottom of the view.
struct FaceTaggingOverlay: ViewModifier {
    let chapter: Chapter
    @State private var queue: [FaceRecord] = []
    @State private var sessionSkipped: Set<UUID> = []

    private var currentFace: FaceRecord? {
        queue.first(where: { !sessionSkipped.contains($0.id) })
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let face = currentFace {
                    FaceTaggingBanner(
                        face:        face,
                        partnerName: chapter.partner?.displayName ?? "them",
                        onConfirm: {
                            guard let partnerID = chapter.partner?.id else { return }
                            try? await FaceIndexService.shared.tag(
                                faceID:    face.id,
                                as:        partnerID,
                                in:        chapter.id
                            )
                            // Remove from queue immediately on confirm
                            queue.removeAll { $0.id == face.id }
                        },
                        onSkip: {
                            sessionSkipped.insert(face.id)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.mtSlide, value: currentFace?.id)
                }
            }
            .task {
                queue = await FaceIndexService.shared.untaggedFaces()
            }
    }
}

extension View {
    func faceTaggingOverlay(for chapter: Chapter) -> some View {
        modifier(FaceTaggingOverlay(chapter: chapter))
    }
}
