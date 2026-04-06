// WaveformView.swift
// Animated bar waveform — live during recording, static snapshot for playback/preview.
// DESIGN.md: accent color (#C8956C), thin bars, voice clip tile and recording step.

import SwiftUI

struct WaveformView: View {
    /// Live audio level 0…1. Only used when isAnimating = true.
    var level: Float = 0
    var isAnimating: Bool = false
    var barCount: Int = 30

    // Pre-generated static heights so the preview looks organic, not uniform.
    @State private var staticHeights: [Float] = []

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.mtAccent)
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
        .onAppear {
            staticHeights = (0..<barCount).map { i in
                // Organic curve: sine wave + randomness, taller in the middle
                let center = Float(barCount - 1) / 2
                let sine   = sin(Float(i) / Float(barCount) * .pi)
                return 0.2 + sine * 0.5 + Float.random(in: -0.1...0.1)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let maxH: CGFloat = 44
        let minH: CGFloat = 3

        if isAnimating {
            // Live: each bar responds to the current level with position-based variance.
            // Bars near the center are taller; edges stay quieter.
            let center   = Float(barCount - 1) / 2
            let distance = abs(Float(index) - center) / center   // 0 at center → 1 at edge
            let h = level * (1 - distance * 0.55) + Float.random(in: -0.08...0.08)
            return minH + CGFloat(max(0.05, min(1, h))) * (maxH - minH)
        } else {
            let h = staticHeights.isEmpty ? 0.5 : staticHeights[index % staticHeights.count]
            return minH + CGFloat(max(0, min(1, h))) * (maxH - minH)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        WaveformView(level: 0.7, isAnimating: true)
        WaveformView(isAnimating: false)
    }
    .padding()
    .background(Color(hex: "#F5EAD8"))
}

