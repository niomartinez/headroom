import Foundation

enum Sandbox {
    /// The App Sandbox sets `APP_SANDBOX_CONTAINER_ID` for sandboxed processes (Release builds, spec §4).
    static func isActive(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !(environment["APP_SANDBOX_CONTAINER_ID"] ?? "").isEmpty
    }
}
