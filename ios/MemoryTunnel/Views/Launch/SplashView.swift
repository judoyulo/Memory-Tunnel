// SplashView.swift
// App launch animation — "entering the tunnel."
//
// Sequence:
//   1. Ring draws itself on (trim path 0→1)
//   2. Amber center fades in + breathes
//   3. Floating particles drift upward
//   4. "tunneling in..." typewriter-types letter by letter
//   5. Everything fades out together
//
// Respects Reduce Motion: instant cross-fade, no particles.

import SwiftUI

struct SplashView: View {
    // Ring draw-on
    @State private var ringTrim: CGFloat = 0
    @State private var ringOpacity: Double = 0

    // Amber center
    @State private var amberScale: CGFloat = 0.3
    @State private var amberOpacity: Double = 0
    @State private var amberBreath: CGFloat = 1.0

    // Typewriter text
    @State private var visibleChars: Int = 0
    private let tagline = "tunneling in..."

    // Particles
    @State private var showParticles = false

    // Overall fade out
    @State private var fadeOut: Double = 1.0

    @State private var animTask: Task<Void, Never>?
    let onFinished: () -> Void

    private let ringSize: CGFloat = 120
    private let ringStroke: CGFloat = 8

    private var reduced: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            // Floating particles (behind ring)
            if showParticles && !reduced {
                SplashParticleField()
            }

            VStack(spacing: 28) {
                // Tunnel mark: ring + amber center
                ZStack {
                    // Ring draws on
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            Color.mtLabel,
                            style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                        )
                        .frame(width: ringSize * 0.68, height: ringSize * 0.68)
                        .rotationEffect(.degrees(-90))
                        .opacity(ringOpacity)

                    // Amber center
                    Circle()
                        .fill(Color.mtAccent)
                        .frame(width: ringSize * 0.21, height: ringSize * 0.21)
                        .scaleEffect(amberScale * amberBreath)
                        .opacity(amberOpacity)
                }
                .frame(width: ringSize, height: ringSize)

                // Typewriter tagline
                if visibleChars > 0 {
                    Text(String(tagline.prefix(visibleChars)))
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.mtSecondary)
                        .transition(.opacity)
                }
            }
        }
        .opacity(fadeOut)
        .onAppear { animTask = Task { await animate() } }
        .onDisappear { animTask?.cancel() }
    }

    @MainActor
    private func animate() async {
        if reduced {
            ringTrim = 1; ringOpacity = 1; amberScale = 1; amberOpacity = 1
            visibleChars = tagline.count
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        // Phase 1: Ring draws on (0→100ms fade in, 0→500ms trim)
        withAnimation(.easeOut(duration: 0.15)) { ringOpacity = 1 }
        withAnimation(.easeOut(duration: 0.6)) { ringTrim = 1.0 }

        // Phase 2: Amber center pops in at 200ms
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            amberScale = 1.0
            amberOpacity = 1
        }

        // Start particles
        showParticles = true

        // Amber breathe loop
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            amberBreath = 1.08
        }

        // Phase 3: Typewriter text starts at 400ms
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        for i in 1...tagline.count {
            guard !Task.isCancelled else { return }
            visibleChars = i
            // Vary typing speed: faster for letters, slight pause at spaces
            let char = tagline[tagline.index(tagline.startIndex, offsetBy: i - 1)]
            let delay: UInt64 = char == " " ? 60_000_000 : 40_000_000
            try? await Task.sleep(nanoseconds: delay)
        }

        // Hold for a beat
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }

        // Phase 4: Everything fades out
        withAnimation(.easeIn(duration: 0.35)) { fadeOut = 0 }

        try? await Task.sleep(nanoseconds: 380_000_000)
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

// MARK: - Floating Particles

/// Ambient particles that drift upward. Warm amber dots of varying sizes.
private struct SplashParticleField: View {
    struct Particle: Identifiable {
        let id: Int
        let x: CGFloat       // 0...1
        let size: CGFloat     // 3...7
        let duration: Double  // 2...4s
        let delay: Double     // 0...1s
        let opacity: Double   // 0.15...0.4
    }

    private let particles: [Particle] = (0..<12).map { i in
        Particle(
            id: i,
            x: CGFloat.random(in: 0.15...0.85),
            size: CGFloat.random(in: 3...6),
            duration: Double.random(in: 2.0...3.5),
            delay: Double.random(in: 0...0.8),
            opacity: Double.random(in: 0.15...0.35)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                ParticleDot(
                    particle: p,
                    bounds: geo.size
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ParticleDot: View {
    let particle: SplashParticleField.Particle
    let bounds: CGSize
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .fill(Color.mtAccent)
            .frame(width: particle.size, height: particle.size)
            .position(
                x: bounds.width * particle.x,
                y: bounds.height * 0.65 + yOffset
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeOut(duration: particle.duration)
                    .delay(particle.delay)
                ) {
                    yOffset = -bounds.height * 0.4
                    opacity = particle.opacity
                }
                // Fade out near the end
                withAnimation(
                    .easeIn(duration: 0.5)
                    .delay(particle.delay + particle.duration - 0.5)
                ) {
                    opacity = 0
                }
            }
    }
}

#Preview {
    SplashView { }
}

