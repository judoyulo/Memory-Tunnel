// ScanProgressRing.swift
// Circular progress indicator for face scanning.
// Activity ring fills as photos are scanned, count in monospace at center,
// orbiting amber dot, rotating status phrases.

import SwiftUI

struct ScanProgressRing: View {
    let scanned: Int
    let total: Int
    let facesFound: Int
    var isDeepScan: Bool = false

    @State private var orbitAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var appeared = false
    @State private var phraseIndex: Int = 0
    @State private var phraseOpacity: Double = 1.0
    @State private var phraseTimer: Task<Void, Never>?

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(scanned) / Double(total), 1.0)
    }

    private var currentPhrase: String {
        let pool = isDeepScan ? Self.deepPhrases : Self.phrases
        return pool[phraseIndex % pool.count]
    }

    private let ringSize: CGFloat = 140
    private let lineWidth: CGFloat = 6

    private static var phrases: [String] { L.scanPhrases }

    // Deep scan phrases — treasure hunt energy
    private static var deepPhrases: [String] { L.deepScanPhrases }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                // Track ring (faint)
                Circle()
                    .stroke(Color.mtLabel.opacity(0.08), lineWidth: lineWidth)
                    .frame(width: ringSize, height: ringSize)

                // Progress ring — amber in deep scan mode
                Circle()
                    .trim(from: 0, to: appeared ? progress : 0)
                    .stroke(
                        isDeepScan ? Color.mtAccent : Color.mtLabel,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)

                // Orbiting dot
                Circle()
                    .fill(Color.mtAccent)
                    .frame(width: 8, height: 8)
                    .offset(y: -(ringSize / 2))
                    .rotationEffect(.degrees(orbitAngle))
                    .opacity(progress < 1.0 ? 0.8 : 0)

                // Center content
                VStack(spacing: 2) {
                    if total > 0 {
                        Text("\(scanned)")
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.mtLabel)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: scanned)

                        Text("/ \(total)")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.mtTertiary)
                    } else {
                        Circle()
                            .fill(Color.mtLabel)
                            .frame(width: 8, height: 8)
                            .scaleEffect(pulseScale)
                    }
                }
            }
            .frame(width: ringSize + 20, height: ringSize + 20)

            // Status text — rotating phrases
            VStack(spacing: 6) {
                Text(currentPhrase)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isDeepScan ? Color.mtAccent : Color.mtSecondary)
                    .opacity(phraseOpacity)
                    .animation(.easeInOut(duration: 0.3), value: phraseOpacity)
                    .id("phrase-\(phraseIndex)")

                if facesFound > 0 {
                    Text(L.facesFound(facesFound))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.mtAccent)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.mtBounce, value: facesFound)
                }
            }
            .frame(height: 44) // Fixed height so layout doesn't jump
        }
        .onAppear {
            appeared = true

            // Orbit animation
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                orbitAngle = 360
            }

            // Pulse animation for pre-total state
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }

            // Start phrase rotation
            phraseIndex = Int.random(in: 0..<Self.phrases.count)
            phraseTimer = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { break }
                    // Fade out
                    phraseOpacity = 0
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { break }
                    // Swap text and fade in
                    phraseIndex += 1
                    phraseOpacity = 1
                }
            }
        }
        .onDisappear {
            phraseTimer?.cancel()
        }
    }
}

#Preview {
    ZStack {
        Color.mtBackground.ignoresSafeArea()
        ScanProgressRing(scanned: 247, total: 800, facesFound: 5)
    }
}
