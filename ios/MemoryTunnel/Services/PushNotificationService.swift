import UIKit
import UserNotifications

/// Registers for APNs and uploads the device token to the server.
final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()
    private override init() { super.init() }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch {
            print("[PushNotificationService] Auth request failed: \(error)")
        }
    }

    /// Called from AppDelegate when APNs returns a device token.
    func didRegister(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                _ = try await APIClient.shared.updateMe(pushToken: tokenString)
            } catch {
                print("[PushNotificationService] Token upload failed: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle foreground notifications — show a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap — route to the relevant screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        NotificationRouter.shared.route(userInfo: info)
        completionHandler()
    }
}

// MARK: - Notification Router

/// Publishes routing decisions so SwiftUI views can react via `@EnvironmentObject`.
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    private init() {}

    @Published var pendingChapterID: String?
    @Published var pendingMemoryID: String?

    func route(userInfo: [AnyHashable: Any]) {
        if let chapterID = userInfo["chapter_id"] as? String {
            pendingChapterID = chapterID
        }
        if let memoryID = userInfo["memory_id"] as? String {
            pendingMemoryID = memoryID
        }
    }

    /// Handle `memorytunnel://` URL scheme (widget taps, Branch deep links).
    /// Format: memorytunnel://chapter/{chapterID}
    func route(url: URL) {
        guard url.scheme == "memorytunnel" else { return }
        if url.host == "chapter", let chapterID = url.pathComponents.dropFirst().first {
            pendingChapterID = chapterID
        }
    }
}
