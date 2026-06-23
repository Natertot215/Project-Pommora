import Foundation

extension ProcessInfo {
    /// True under the XCTest host (which sets this env var). Launch-time modals /
    /// permission prompts must early-return on it — quirk #12: a modal blocks the
    /// test runner from connecting.
    static var isRunningXCTests: Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
