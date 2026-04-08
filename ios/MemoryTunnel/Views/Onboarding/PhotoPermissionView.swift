import SwiftUI

/// Screen 5: Warm photo permission request before face scanning.
/// Explains what the scan does and that everything stays on-device.
struct PhotoPermissionView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon — emotional peak, accent justified
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.mtAccent)
                    .padding(.bottom, Spacing.lg)

                // Headline
                Text(L.seeThePeople)
                    .font(.mtEmptyTitle)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Spacing.md)

                // Explanation
                Text(L.photoPermissionBody)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Spacer()
                Spacer()

                // CTAs
                VStack(spacing: Spacing.md) {
                    PrimaryButton(title: L.allowPhotos, isLoading: false) {
                        onAllow()
                    }

                    Button(L.skipThisStep) {
                        onSkip()
                    }
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .stroke(Color.mtLabel, lineWidth: 1.5)
                    )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
