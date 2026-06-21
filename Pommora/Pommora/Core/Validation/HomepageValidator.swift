import Foundation

enum HomepageValidator {
    enum ValidationError: Error, Equatable {
        case fileMissing
    }

    /// Verifies the canonical homepage file exists.
    /// Manager is responsible for ensuring it does (seeds on first load).
    static func validateSingleton(in nexus: Nexus) throws {
        let url = NexusPaths.homepageURL(in: nexus)
        if !Filesystem.fileExists(at: url) {
            throw ValidationError.fileMissing
        }
    }
}
