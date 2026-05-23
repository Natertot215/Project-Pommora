import Foundation
import Testing

@testable import Pommora

@Suite("ItemValidator")
struct ItemValidatorTests {

    @Test("happy path: valid title + resolving tier IDs + matching property values")
    func happy() throws {
        let spaceID = ULID.generate()
        let topicID = ULID.generate()
        let projectID = ULID.generate()
        let space = Space(
            id: spaceID, title: "S", color: .blue, icon: nil,
            blocks: [], modifiedAt: Date())
        let topic = Topic(
            id: topicID, title: "T", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let project = Project(
            id: projectID, title: "U", parents: ["01HX"],
            linkedRelations: [], icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { id in id == spaceID ? space : nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { id in id == projectID ? project : nil },
            lookupVault: { _ in nil }
        )
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [
                PropertyDefinition(
                    name: "status", type: .select,
                    selectOptions: [PropertyDefinition.SelectOption(value: "Active", label: "Active", color: nil)])
            ],
            views: [], modifiedAt: Date()
        )
        try ItemValidator.validate(
            title: "Buy groceries",
            tier1: [spaceID], tier2: [topicID], tier3: [projectID],
            properties: ["status": .select("Active")],
            vault: vault,
            existingSiblings: [],
            context: context
        )
    }

    @Test("tier1 ID resolving to a Topic (wrong tier) throws")
    func tier1WrongTier() {
        let topicID = ULID.generate()
        let topic = Topic(
            id: topicID, title: "T", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { _ in nil },
            lookupVault: { _ in nil }
        )
        let vault = makeVault(properties: [])
        #expect(throws: ItemValidator.ValidationError.tierMismatch(expectedTier: 1, id: topicID)) {
            try ItemValidator.validate(
                title: "X", tier1: [topicID], tier2: [], tier3: [],
                properties: [:], vault: vault,
                existingSiblings: [], context: context
            )
        }
    }

    @Test("property value of wrong type throws")
    func wrongPropertyType() {
        let vault = makeVault(properties: [
            PropertyDefinition(name: "count", type: .number)
        ])
        #expect(throws: ItemValidator.ValidationError.propertyTypeMismatch(name: "count")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["count": .checkbox(true)],  // wrong type
                vault: vault,
                existingSiblings: [], context: .empty
            )
        }
    }

    @Test("property not in vault schema throws")
    func unknownProperty() {
        let vault = makeVault(properties: [])
        #expect(throws: ItemValidator.ValidationError.unknownProperty(name: "phantom")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["phantom": .select("a")],
                vault: vault,
                existingSiblings: [], context: .empty
            )
        }
    }

    private func makeVault(properties: [PropertyDefinition]) -> PageType {
        PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: properties, views: [], modifiedAt: Date())
    }
}
