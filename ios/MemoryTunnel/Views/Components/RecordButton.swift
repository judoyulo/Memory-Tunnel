// RecordButton.swift
// Hold-to-record button with 60-second progress ring and haptic feedback.
// DESIGN.md: accent ring, near-black fill when recording, 44pt minimum touch target.

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let duration: TimeInterval          // 0…60 current recording duration
    let onStart: () -> Void
    let onStop:  () -> Void

    private let maxDuration: TimeInterval = 60

    var body: some View {
        ZStack {
            // Filled circle — background state
            Circle()
                .fill(isRecording ? Color.mtLabel : Color.mtSurface)
                .frame(width: 72, height: 72)

            // Accent progress ring — fills clockwise as recording progresses
            if isRecording {
                Circle()
                    .trim(from: 0, to: CGFloat(min(duration / maxDuration, 1)))
                    .stroke(Color.mtAccent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 82, height: 82)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: duration)
            } else {
                // Idle border
                Circle()
                    .strokeBorder(Color.mtLabel.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 82, height: 82)
            }

            // Icon
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isRecording ? Color.mtBackground : Color.mtLabel)
        }
        // Hold-to-record gesture: press begins recording, release stops it.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isRecording else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onStart()
                }
                .onEnded { _ in
                    guard isRecording else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onStop()
                }
        )
        .accessibilityLabel(isRecording ? "Stop recording" : "Hold to record voice clip")
        .accessibilityAddTraits(.isButton)
    }
}
