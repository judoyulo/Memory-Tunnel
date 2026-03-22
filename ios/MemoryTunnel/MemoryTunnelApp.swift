import SwiftUI

@main
struct MemoryTunnelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var router = NotificationRouter.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .environmentObject(router)
            .preferredColorScheme(.light)   // Design system: light only (cream bg)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Branch.io deferred deep link init
        // Branch.getInstance().initSession(launchOptions: launchOptions) { ... }
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
