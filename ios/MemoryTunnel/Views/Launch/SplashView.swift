// SplashView.swift
// App launch animation — "entering the tunnel."
//
// Shown for ~1 second on cold launch, then cross-fades to main content.
// The tunnel mark scales in (0.80 → 1.0) then the whole view fades out.
// Respects Reduce Motion: instant cross-fade, no scale.

import SwiftUI

struct SplashView: View {
    @State private var markScale: CGFloat = 0.80
    @State private var markOpacity: Double = 0
    @State private var innerPulse: CGFloat = 1.0
    @State private var animTask: Task<Void, Never>?
    let onFinished: () -> Void

    private var reduced: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            Color(red: 0.961, green: 0.918, blue: 0.847)
                .ignoresSafeArea()

            AppIconView(size: 120, innerScale: innerPulse)
                .scaleEffect(reduced ? 1 : markScale)
                .opacity(markOpacity)
        }
        .onAppear { animTask = Task { await animate() } }
        .onDisappear { animTask?.cancel() }
    }

    @MainActor
    private func animate() async {
        if reduced {
            markOpacity = 1
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        // Phase 1: mark enters (scale up + fade in)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            markScale = 1.0
            markOpacity = 1
        }

        // Phase 2: amber inner circle pulses gently once (at 350ms)
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.25)) { innerPulse = 1.08 }
        withAnimation(.easeInOut(duration: 0.25).delay(0.25)) { innerPulse = 1.0 }

        // Phase 3: whole view fades out (at 850ms total)
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.28)) { markOpacity = 0 }

        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

#Preview {
    SplashView { }
}
