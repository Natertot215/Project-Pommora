import Foundation
import Testing
@testable import Pommora

@Suite("SubtopicValidator")
struct SubtopicValidatorTests {

    @Test("happy path: exactly one parent resolving to a Topic + correct file location")
    func happyPath() throws {
        let topicID = ULID.generate()
        let topic = Topic(id: topicID, title: "Productivity", parents: [],
                          icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topicID ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        try SubtopicValidator.validate(
            title: "GTD method",
            parents: [topicID],
            fileLocation: SubtopicValidator.FileLocation(parentFolderTitle: "Productivity"),
            existing: [],
            context: context
        )
    }

    @Test("title rules apply")
    func titleRules() {
        let context = NexusContext.empty
        #expect(throws: SubtopicValidator.ValidationError.emptyTitle) {
            try SubtopicValidator.validate(
                title: "", parents: ["01H"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: context
            )
        }
    }

    @Test("zero parents throws missingParent")
    func zeroParents() {
        #expect(throws: SubtopicValidator.ValidationError.missingParent) {
            try SubtopicValidator.validate(
                title: "X", parents: [],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("two parents throws tooManyParents")
    func tooManyParents() {
        #expect(throws: SubtopicValidator.ValidationError.tooManyParents) {
            try SubtopicValidator.validate(
                title: "X", parents: ["01HA", "01HB"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("parent ID that doesn't resolve to a Topic throws")
    func parentNotFound() {
        #expect(throws: SubtopicValidator.ValidationError.parentNotFound("01HZZ")) {
            try SubtopicValidator.validate(
                title: "X", parents: ["01HZZ"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("file location title not matching parent Topic title throws")
    func locationMismatch() {
        let topicID = ULID.generate()
        let topic = Topic(id: topicID, title: "Productivity", parents: [],
                          icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topicID ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        #expect(throws: SubtopicValidator.ValidationError.fileLocationMismatch) {
            try SubtopicValidator.validate(
                title: "X", parents: [topicID],
                fileLocation: .init(parentFolderTitle: "WrongFolder"),
                existing: [], context: context
            )
        }
    }

    @Test("duplicate title within same parent Topic throws")
    func duplicate() {
        let topicID = ULID.generate()
        let topic = Topic(id: topicID, title: "P", parents: [],
                          icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topicID ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        let existing = [makeSubtopic(title: "GTD", parents: [topicID])]
        #expect(throws: SubtopicValidator.ValidationError.duplicateTitle) {
            try SubtopicValidator.validate(
                title: "gtd", parents: [topicID],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: existing, context: context
            )
        }
    }

    private func makeTopic(title: String) -> Topic {
        Topic(id: ULID.generate(), title: title, parents: [],
              icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeSubtopic(title: String, parents: [String]) -> Subtopic {
        Subtopic(id: ULID.generate(), title: title, parents: parents,
                 linkedRelations: [], icon: nil, blocks: [], modifiedAt: Date())
    }
}
