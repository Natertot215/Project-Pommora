import Foundation
import Testing
@testable import Pommora

@Suite("PageValidator")
struct PageValidatorTests {

    @Test("happy path passes")
    func happy() throws {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            vault: vault,
            existingInCollection: [],
            context: .empty
        )
    }

    @Test("created_at = zero-epoch is treated as missing")
    func missingCreatedAt() {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.missingCreatedAt) {
            try PageValidator.validate(
                title: "X",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 0),
                vault: vault,
                existingInCollection: [],
                context: .empty
            )
        }
    }

    @Test("duplicate title in same Collection throws")
    func duplicate() throws {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        let existing = [makePageMeta(title: "Notes")]
        #expect(throws: PageValidator.ValidationError.duplicateTitle) {
            try PageValidator.validate(
                title: "NOTES",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 1),
                vault: vault,
                existingInCollection: existing,
                context: .empty
            )
        }
    }

    private func makePageMeta(title: String) -> PageMeta {
        PageMeta(
            id: ULID.generate(),
            title: title,
            url: URL(fileURLWithPath: "/tmp/x/\(title).md"),
            frontmatter: PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
    }
}
