// WelcomeView.swift
// Pre-auth walkthrough: 3 screens showing what Memory Tunnel does.
// Shows the value BEFORE asking for phone number.
//
// Screen 1: "your photos hide buried memories" — Today Tab preview
// Screen 2: "build a chapter with someone"     — Chapter timeline preview
// Screen 3: "share what you find"              — Share card preview
//
// Parallax scroll on preview images. Pulsing CTA on last screen.
// Swipeable TabView with page dots. "get started" available on every page.

import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void

    @State private var currentPage = 0
    @State private var appeared = false
    @State private var ctaPulse: CGFloat = 1.0

    private var pages: [(headline: String, subtext: String)] {
        [
            (L.walkthrough1Headline, L.walkthrough1Subtext),
            (L.walkthrough2Headline, L.walkthrough2Subtext),
            (L.walkthrough3Headline, L.walkthrough3Subtext),
        ]
    }

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        WalkthroughPage(
                            headline: page.headline,
                            subtext: page.subtext,
                            pageIndex: index,
                            currentPage: currentPage
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // CTA button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        onGetStarted()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? L.continueBtn : L.getStarted)
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .scaleEffect(currentPage == pages.count - 1 ? ctaPulse : 1.0)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)

                // "skip" text on non-last pages
                if currentPage < pages.count - 1 {
                    Button(action: onGetStarted) {
                        Text(L.skip)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mtTertiary)
                    }
                    .padding(.bottom, Spacing.lg)
                }
            }
        }
        .onAppear {
            appeared = true
            // Pulse CTA on last page
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                ctaPulse = 1.03
            }
        }
    }
}

// MARK: - Single Walkthrough Page

private struct WalkthroughPage: View {
    let headline: String
    let subtext: String
    let pageIndex: Int
    let currentPage: Int

    // Parallax: offset image based on distance from current page
    private var parallaxOffset: CGFloat {
        CGFloat(pageIndex - currentPage) * -30
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Headline (lowercase monospace)
            Text(headline)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.mtLabel)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Live-rendered mock preview with parallax + rotation
            WalkthroughMockup(pageIndex: pageIndex)
                .frame(maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .rotationEffect(.degrees(pageIndex == 1 ? -2 : (pageIndex == 2 ? 2 : 0)))
                .offset(x: parallaxOffset)
                .padding(.horizontal, Spacing.xl)

            // Subtext
            Text(subtext)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Live Mockups (renders real-looking app UI inline)

private struct WalkthroughMockup: View {
    let pageIndex: Int

    var body: some View {
        switch pageIndex {
        case 0:  mockFeedCard
        case 1:  mockTimeline
        default: mockShareCard
        }
    }

    // Page 1: Mock feed card (full-bleed photo with overlay)
    private var mockFeedCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Use a warm gradient to simulate a photo
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.65, blue: 0.45),
                    Color(red: 0.55, green: 0.35, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Simulated face area (light circle, like a person)
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 100, height: 100)
                .offset(x: 80, y: -120)

            // Bottom gradient
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.6)],
                startPoint: UnitPoint(x: 0.5, y: 0.55),
                endPoint: .bottom
            )

            // Overlay text
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                Text(L.newFace)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.4, green: 0.7, blue: 0.9).opacity(0.85))
                    .clipShape(Capsule())

                Text("Alex")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)

                Text("May 2023")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))

                // Mock button
                Text(L.startAMemoryLane)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 4)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }

    // Page 2: Mock cinematic timeline
    private var mockTimeline: some View {
        VStack(spacing: 6) {
            // Mock photo cards at different scales (cinematic feel)
            mockTimelineCard(opacity: 0.5, height: 50, label: "Barcelona, 2022")
            mockTimelineCard(opacity: 0.7, height: 60, label: "Summer 2023")
            // Hero card (center, full opacity)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.60, blue: 0.75),
                        Color(red: 0.25, green: 0.40, blue: 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("December 2023")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 2) {
                        Image(systemName: "mappin")
                            .font(.system(size: 7))
                        Text("Tokyo")
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            mockTimelineCard(opacity: 0.7, height: 60, label: "New Year 2024")
            mockTimelineCard(opacity: 0.5, height: 50, label: "March 2024")
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Color.mtBackground)
    }

    private func mockTimelineCard(opacity: Double, height: CGFloat, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.mtSurface)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Color.mtTertiary)
                .padding(6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .opacity(opacity)
    }

    // Page 3: Mock share card (time capsule style)
    private var mockShareCard: some View {
        VStack(spacing: 12) {
            // Time capsule card preview
            VStack(spacing: 8) {
                Text("3 years ago")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.mtLabel.opacity(0.85))

                // Mock photo
                LinearGradient(
                    colors: [
                        Color(red: 0.75, green: 0.55, blue: 0.40),
                        Color(red: 0.60, green: 0.40, blue: 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)

                Text("April 2023 · Barcelona")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mtSecondary)

                Text("memory tunnel")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.mtTertiary.opacity(0.5))
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.mtBackground)

            // Mock style picker pills
            HStack(spacing: 8) {
                mockPill(L.timeCapsule, selected: true)
                mockPill(L.excavation, selected: false)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Color.mtSurface)
    }

    private func mockPill(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(selected ? Color.mtBackground : Color.mtTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.mtLabel : Color.mtLabel.opacity(0.06))
            .clipShape(Capsule())
    }
}
