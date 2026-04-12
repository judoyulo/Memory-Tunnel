// ReconnectionCardView.swift
// Full-bleed reconnection card for the Today Tab.
// Shows a photo of someone you've lost touch with and prompts reconnection.

import SwiftUI
import Photos

struct ReconnectionCardView: View {
    let candidate: ReconnectionCandidate
    @State private var photo: UIImage?
    @State private var isLoading = true
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showSendFlow = false
    @State private var showChapterCreation = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed photo
            GeometryReader { geo in
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.mtSurface
                    if isLoading { ProgressView() }
                }
            }
            .ignoresSafeArea()

            // Gradient
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: UnitPoint(x: 0.5, y: 0.65),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Spacer()

                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.mtAccent).frame(width: 6, height: 6)
                    Text(candidate.decayLabel)
                        .font(.mtCaption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }

                Text(candidate.name.isEmpty ? L.someoneWorthRemembering : candidate.name)
                    .font(.mtDisplay)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(contextLine)
                    .font(.mtBody)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)

                // Two CTAs: Start chapter + Share card
                VStack(spacing: Spacing.sm) {
                    // Primary: Start a chapter / send a memory
                    Button {
                        showChapterCreation = true
                    } label: {
                        Text(L.startAMemoryLane)
                            .font(.mtButton)
                            .foregroundStyle(Color.mtBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.mtLabel)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }

                    // Secondary: Share as card
                    Button {
                        generateShareCard()
                    } label: {
                        Text(L.share)
                            .font(.mtButton)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                            )
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .task { await loadPhoto() }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(items: [shareImage])
            }
        }
        .sheet(isPresented: $showChapterCreation) {
            // Create a chapter for this person with the photo pre-loaded
            InviteFlowView()
        }
    }

    private var contextLine: String {
        let days = candidate.daysSinceLastPhoto
        let photos = candidate.photoCount
        if days > 365 {
            let years = days / 365
            return L.yearsAgo(years)
        } else if days > 30 {
            let months = days / 30
            return L.monthsAgo(months)
        } else {
            return L.daysAgo(days)
        }
    }

    private func loadPhoto() async {
        isLoading = true
        photo = await ReconnectionService.shared.loadFullImage(for: candidate.bestPhoto)
        isLoading = false
    }

    private func generateShareCard() {
        guard let photo else { return }
        shareImage = ShareableCardRenderer.renderStoryCard(
            photo: photo,
            personName: candidate.name,
            date: candidate.newestDate,
            locationName: nil
        )
        showShareSheet = true
    }
}
