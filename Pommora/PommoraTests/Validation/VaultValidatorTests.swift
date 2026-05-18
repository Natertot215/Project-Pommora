import Foundation
import Testing

@testable import Pommora

@Suite("VaultValidator")
struct VaultValidatorTests {

    @Test("valid title passes")
    func valid() throws {
        try VaultValidator.validate(title: "Planner", existing: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: VaultValidator.ValidationError.emptyTitle) {
            try VaultValidator.validate(title: "  ", existing: [])
        }
        #expect(throws: VaultValidator.ValidationError.invalidTitleCharacters) {
            try VaultValidator.validate(title: "A:B", existing: [])
        }
    }

    @Test("duplicate vault title throws")
    func duplicate() {
        let existing = [makeVault(title: "Planner")]
        #expect(throws: VaultValidator.ValidationError.duplicateTitle) {
            try VaultValidator.validate(title: "PLANNER", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameSelf() throws {
        let v = makeVault(title: "Planner")
        try VaultValidator.validate(title: "Planner", existing: [v], excluding: v)
    }

    private func makeVault(title: String) -> Vault {
        Vault(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date())
    }
}
