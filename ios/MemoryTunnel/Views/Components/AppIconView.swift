// AppIconView.swift
// The Memory Tunnel app icon mark — "The Tunnel."
//
// Two concentric circles on warm cream:
//   Outer ring: near-black (#1C1C1E), stroke 6.8% of size
//   Inner circle: amber accent (#C8956C), solid, 21% of size
//   Gap: ~17% — creates optical tunnel depth
//
// This is the design source of truth. To export as PNG for the App Store:
//   1. Open this file in Xcode
//   2. In the canvas preview, right-click the 1024pt preview → "Export as PNG"
//   3. Drop the exported PNG into Assets.xcassets/AppIcon.appiconset/
//
// Scales cleanly from 20pt (notification icon) to 1024pt (App Store).

import SwiftUI

struct AppIconView: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Color(red: 0.961, green: 0.918, blue: 0.847)

            // Outer ring
            Circle()
                .stroke(Color(red: 0.110, green: 0.110, blue: 0.118), lineWidth: size * 0.068)
                .frame(width: size * 0.68, height: size * 0.68)

            // Inner circle — amber accent (emotional peak)
            Circle()
                .fill(Color(red: 0.784, green: 0.584, blue: 0.424))
                .frame(width: size * 0.21, height: size * 0.21)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Home screen (60pt @3x = 180pt)", traits: .sizeThatFitsLayout) {
    AppIconView(size: 180)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
}

#Preview("App Store (1024pt)", traits: .sizeThatFitsLayout) {
    AppIconView(size: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 225, style: .continuous))
}
