import SwiftUI
import BranchSDK

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
                // Branch.io Universal Link / URI scheme handler
                Branch.getInstance().handleDeepLink(url)
                // Widget taps use memorytunnel:// scheme — route to NotificationRouter
                NotificationRouter.shared.route(url: url)
            }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Branch.io deferred deep link — preserves invitation token through App Store install
        Branch.getInstance().initSession(launchOptions: launchOptions) { params, error in
            guard let params = params as? [String: AnyObject], error == nil else { return }

            // Branch passes the invitation_token embedded in the web preview page
            if let token = params["invitation_token"] as? String {
                DeepLinkStore.shared.pendingInvitationToken = token
            }
        }
        return true
    }

    // Universal Links (for Branch)
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        Branch.getInstance().continue(userActivity)
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
