import SwiftUI

/// Shown when a user opens the app via a Branch.io invitation link before signing up.
/// Displays "X invited you to a chapter" with a preview, then routes to auth.
struct InvitedLandingView: View {
    @EnvironmentObject var appState: AppState
    @State private var preview: InvitationPreview?
    @State private var isLoading = true
    @State private var showAuth = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if showAuth {
                OnboardingView()
            } else if let errorMessage {
                // API failed — show error with retry
                VStack(spacing: Spacing.lg) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.mtTertiary)
                    Text("Couldn't load invitation")
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                    Text(errorMessage)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        self.errorMessage = nil
                        isLoading = true
                        Task { await loadPreview() }
                    }
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    Spacer()
                    Button("Skip to sign up") { showAuth = true }
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                        .padding(.bottom, Spacing.xxl)
                }
                .padding(Spacing.xl)
            } else if let preview {
                invitedContent(preview)
            } else {
                // Token invalid or expired — fall through to regular onboarding
                OnboardingView()
            }
        }
        .task { await loadPreview() }
    }

    @ViewBuilder
    private func invitedContent(_ preview: InvitationPreview) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Preview image
            if let url = preview.previewImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.mtSurface
                }
                .frame(height: 280)
                .clipped()
                .clipped()  // edge-to-edge per DESIGN.md — no corner radius on preview photos
                .padding(.horizontal, Spacing.xl)
            }

            // Invitation message
            VStack(spacing: Spacing.sm) {
                Text("\(preview.inviterName) invited you")
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)

                if let name = preview.chapterName {
                    Text("to the chapter \"\(name)\"")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                }
            }
            .padding(.top, Spacing.lg)

            Spacer()

            // CTAs
            VStack(spacing: Spacing.md) {
                PrimaryButton(title: "Join & Add Your Memories", isLoading: false) {
                    showAuth = true
                }

                Text("You'll create an account to join this chapter.")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
    }

    private func loadPreview() async {
        guard let token = DeepLinkStore.shared.pendingInvitationToken else {
            isLoading = false
            return
        }

        do {
            preview = try await APIClient.shared.fetchInvitationPreview(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
