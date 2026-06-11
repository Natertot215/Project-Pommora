import Foundation
import Testing

@testable import Pommora

@Suite("TopicValidator")
struct TopicValidatorTests {

    @Test("title rules apply same as Area")
    func titleRules() {
        #expect(throws: TopicValidator.ValidationError.emptyTitle) {
            try TopicValidator.validate(title: "", existing: [])
        }
        #expect(throws: TopicValidator.ValidationError.invalidTitleCharacters) {
            try TopicValidator.validate(title: "A/B", existing: [])
        }
    }

    @Test("duplicate title within nexus throws")
    func duplicate() {
        let existing = [makeTopic(title: "Productivity")]
        #expect(throws: TopicValidator.ValidationError.duplicateTitle) {
            try TopicValidator.validate(
                title: "productivity", existing: existing
            )
        }
    }

    @Test("valid title with no duplicates passes")
    func validTitle() throws {
        try TopicValidator.validate(title: "Workflows", existing: [])
    }

    private func makeTopic(title: String) -> Topic {
        Topic(
            id: ULID.generate(), title: title,
            icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeArea(title: String) -> Area {
        Area(
            id: ULID.generate(), title: title, color: .blue,
            icon: nil, blocks: [], modifiedAt: Date())
    }
}
