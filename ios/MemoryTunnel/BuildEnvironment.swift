import Foundation

enum BuildEnvironment {
    /// True for Debug builds AND TestFlight builds. False for App Store production.
    /// Detection: TestFlight builds have a sandbox receipt named "sandboxReceipt".
    static var isDevOrTestFlight: Bool {
        #if DEBUG
        return true
        #else
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
