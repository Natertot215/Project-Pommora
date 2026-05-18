import Foundation
import Testing

@testable import Pommora

@Suite("HomepageValidator")
struct HomepageValidatorTests {

    @Test("validateSingleton passes when exactly one file at canonical location")
    func happy() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(Homepage.defaultSeed(), to: url)
        try HomepageValidator.validateSingleton(in: nexus)
    }

    @Test("validateSingleton throws when file missing")
    func missing() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(throws: HomepageValidator.ValidationError.fileMissing) {
            try HomepageValidator.validateSingleton(in: nexus)
        }
    }
}
