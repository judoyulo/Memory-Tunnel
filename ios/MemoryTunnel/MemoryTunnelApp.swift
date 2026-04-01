import SwiftUI
#if canImport(BranchSDK)
import BranchSDK
#endif

@main
struct MemoryTunnelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var router = NotificationRouter.shared
    @StateObject private var appState = AppState()

    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if appState.isAuthenticated {
                        ContentView()
                    } else if DeepLinkStore.shared.pendingInvitationToken != nil {
                        InvitedLandingView()
                    } else {
                        OnboardingView()
                    }
                }
                .environmentObject(appState)
                .environmentObject(router)

                if showSplash {
                    SplashView { showSplash = false }
                        .transition(.opacity.animation(.mtFade))
                        .zIndex(1)
                }
            }
            .animation(.mtFade, value: showSplash)
            .preferredColorScheme(.light)   // Design system: light only (cream bg)
            .onOpenURL { url in
                #if canImport(BranchSDK)
                Branch.getInstance().handleDeepLink(url)
                #endif
                NotificationRouter.shared.route(url: url)
            }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if canImport(BranchSDK)
        // Branch.io deferred deep link — preserves invitation token through App Store install
        Branch.getInstance().initSession(launchOptions: launchOptions) { params, error in
            guard let params = params as? [String: AnyObject], error == nil else { return }
            if let token = params["invitation_token"] as? String {
                DeepLinkStore.shared.pendingInvitationToken = token
            }
        }
        #endif
        return true
    }

    // Universal Links (for Branch)
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        #if canImport(BranchSDK)
        Branch.getInstance().continue(userActivity)
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationService.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] APNs registration failed: \(error)")
    }
}

// MARK: - DeepLinkStore
// Holds deferred deep link data between AppDelegate (Branch callback)
// and OnboardingViewModel (where the token is consumed during OTP verify).

@MainActor
final class DeepLinkStore: ObservableObject {
    static let shared = DeepLinkStore()
    @Published var pendingInvitationToken: String?
    private init() {}
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasChapters = false

    var isAuthenticated: Bool { currentUser != nil && TokenStore.shared.isAuthenticated }

    init() {
        // Restore session on launch
        if TokenStore.shared.isAuthenticated {
            Task { await loadCurrentUser() }
        }
    }

    func loadCurrentUser() async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await APIClient.shared.me()
            // Check if user has chapters (for Today tab empty state)
            if let chapters = try? await APIClient.shared.chapters() {
                hasChapters = !chapters.isEmpty
            }
        } catch {
            // Token expired or revoked — force re-auth
            TokenStore.shared.token = nil
        }
    }

    func signOut() {
        TokenStore.shared.token = nil
        currentUser = nil
    }
}
