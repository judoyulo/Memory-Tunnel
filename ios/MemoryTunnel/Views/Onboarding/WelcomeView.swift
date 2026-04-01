import SwiftUI

/// Screen 1: Welcome landing page. Warm introduction to the app before any login.
/// Shows what Memory Tunnel does and invites the user to get started.
struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App identity
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "tunnel.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.mtTertiary)

                    Text("Memory Tunnel")
                        .font(.mtDisplay)
                        .foregroundStyle(Color.mtLabel)
                }
                .padding(.bottom, Spacing.xl)

                // Value proposition
                VStack(spacing: Spacing.md) {
                    Text("Stay close to the people\nwho matter most.")
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                        .multilineTextAlignment(.center)

                    Text("Share photos, voice clips, and memories\nwith the people from every chapter of your life.\nPrivate. Warm. Just for you two.")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()
                Spacer()

                // CTA
                PrimaryButton(title: "Get Started", isLoading: false) {
                    onGetStarted()
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
    }
}
