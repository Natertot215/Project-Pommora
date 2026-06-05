import Foundation
import Testing

@testable import Pommora

@Suite("ProjectValidator")
struct ProjectValidatorTests {

    @Test("happy path: exactly one parent resolving to a Topic + correct file location")
    func happyPath() throws {
        let topicID = ULID.generate()
        let topic = Topic(
            id: topicID, title: "Productivity", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { _ in nil },
            lookupVault: { _ in nil }
        )
        try ProjectValidator.validate(
            title: "GTD method",
            parents: [topicID],
            fileLocation: ProjectValidator.FileLocation(parentFolderTitle: "Productivity"),
            existing: [],
            context: context
        )
    }

    @Test("title rules apply")
    func titleRules() {
        let context = NexusContext.empty
        #expect(throws: ProjectValidator.ValidationError.emptyTitle) {
            try ProjectValidator.validate(
                title: "", parents: ["01H"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: context
            )
        }
    }

    @Test("zero parents throws missingParent")
    func zeroParents() {
        #expect(throws: ProjectValidator.ValidationError.missingParent) {
            try ProjectValidator.validate(
                title: "X", parents: [],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("two parents throws tooManyParents")
    func tooManyParents() {
        #expect(throws: ProjectValidator.ValidationError.tooManyParents) {
            try ProjectValidator.validate(
                title: "X", parents: ["01HA", "01HB"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("parent ID that doesn't resolve to a Topic throws")
    func parentNotFound() {
        #expect(throws: ProjectValidator.ValidationError.parentNotFound("01HZZ")) {
            try ProjectValidator.validate(
                title: "X", parents: ["01HZZ"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("file location title not matching parent Topic title throws")
    func locationMismatch() {
        let topicID = ULID.generate()
        let topic = Topic(
            id: topicID, title: "Productivity", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { _ in nil },
            lookupVault: { _ in nil }
        )
        #expect(throws: ProjectValidator.ValidationError.fileLocationMismatch) {
            try ProjectValidator.validate(
                title: "X", parents: [topicID],
                fileLocation: .init(parentFolderTitle: "WrongFolder"),
                existing: [], context: context
            )
        }
    }

    @Test("duplicate title within same parent Topic throws")
    func duplicate() {
        let topicID = ULID.generate()
        let topic = Topic(
            id: topicID, title: "P", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { _ in nil },
            lookupVault: { _ in nil }
        )
        let existing = [makeProject(title: "GTD", parents: [topicID])]
        #expect(throws: ProjectValidator.ValidationError.duplicateTitle) {
            try ProjectValidator.validate(
                title: "gtd", parents: [topicID],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: existing, context: context
            )
        }
    }

    private func makeTopic(title: String) -> Topic {
        Topic(
            id: ULID.generate(), title: title, parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeProject(title: String, parents: [String]) -> Project {
        Project(
            id: ULID.generate(), title: title, parents: parents,
            projectLinks: [], icon: nil, blocks: [], modifiedAt: Date())
    }
}
