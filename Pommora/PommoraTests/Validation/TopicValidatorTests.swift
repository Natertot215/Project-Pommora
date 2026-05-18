import Foundation
import Testing

@testable import Pommora

@Suite("TopicValidator")
struct TopicValidatorTests {

    @Test("empty parents allowed")
    func emptyParents() throws {
        try TopicValidator.validate(
            title: "Loose", parents: [], existing: [], context: .empty
        )
    }

    @Test("title rules apply same as Space")
    func titleRules() {
        #expect(throws: TopicValidator.ValidationError.emptyTitle) {
            try TopicValidator.validate(title: "", parents: [], existing: [], context: .empty)
        }
        #expect(throws: TopicValidator.ValidationError.invalidTitleCharacters) {
            try TopicValidator.validate(title: "A/B", parents: [], existing: [], context: .empty)
        }
    }

    @Test("duplicate title within nexus throws")
    func duplicate() {
        let existing = [makeTopic(title: "Productivity")]
        #expect(throws: TopicValidator.ValidationError.duplicateTitle) {
            try TopicValidator.validate(
                title: "productivity", parents: [], existing: existing, context: .empty
            )
        }
    }

    @Test("parent ID that doesn't resolve to a Space throws parentNotFound")
    func parentMissing() {
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { _ in nil },
            lookupSubtopic: { _ in nil },
            lookupVault: { _ in nil }
        )
        #expect(throws: TopicValidator.ValidationError.parentNotFound("01HZZ")) {
            try TopicValidator.validate(
                title: "X", parents: ["01HZZ"], existing: [], context: context
            )
        }
    }

    @Test("parent ID that resolves to a Space passes")
    func parentResolves() throws {
        let spaceID = ULID.generate()
        let space = Space(
            id: spaceID, title: "Work", color: .blue,
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { id in id == spaceID ? space : nil },
            lookupTopic: { _ in nil },
            lookupSubtopic: { _ in nil },
            lookupVault: { _ in nil }
        )
        try TopicValidator.validate(
            title: "Productivity", parents: [spaceID], existing: [], context: context
        )
    }

    private func makeTopic(title: String, parents: [String] = []) -> Topic {
        Topic(
            id: ULID.generate(), title: title, parents: parents,
            icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeSpace(title: String) -> Space {
        Space(
            id: ULID.generate(), title: title, color: .blue,
            icon: nil, blocks: [], modifiedAt: Date())
    }
}
