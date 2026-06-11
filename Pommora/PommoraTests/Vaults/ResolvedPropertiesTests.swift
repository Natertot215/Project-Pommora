import Foundation
import Testing

@testable import Pommora

@Suite("ResolvedProperties")
struct ResolvedPropertiesTests {
    private let tierConfig = TierConfig.defaultSeed()

    // MARK: - PageType

    @Test("PageType resolvedProperties includes all three tier IDs")
    func pageTypeIncludesTiers() {
        let pageType = PageType(
            id: "01HPTYPE",
            title: "Notes",
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let resolved = pageType.resolvedProperties(tierConfig: tierConfig)
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test("PageType stored properties does NOT contain tier IDs")
    func pageTypeStoredPropertiesExcludesTiers() {
        let pageType = PageType(
            id: "01HPTYPE",
            title: "Notes",
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        #expect(!pageType.properties.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(!pageType.properties.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!pageType.properties.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test("PageType tier1 resolves to Areas with default TierConfig")
    func pageTypeTier1ResolvesToAreas() {
        let pageType = PageType(
            id: "01HPTYPE",
            title: "Notes",
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let resolved = pageType.resolvedProperties(tierConfig: tierConfig)
        let tier1 = resolved.first { $0.id == ReservedPropertyID.tier1 }
        #expect(tier1?.name == "Areas")
    }

    // MARK: - AgendaTaskSchema

    @Test("AgendaTaskSchema resolvedProperties includes all three tier IDs")
    func agendaTaskSchemaIncludesTiers() {
        let schema = AgendaTaskSchema.defaultSeed()
        let resolved = schema.resolvedProperties(tierConfig: tierConfig)
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test("AgendaTaskSchema stored properties does NOT contain tier IDs")
    func agendaTaskSchemaStoredPropertiesExcludesTiers() {
        let schema = AgendaTaskSchema.defaultSeed()
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier3 })
    }

    // MARK: - AgendaEventSchema

    @Test("AgendaEventSchema resolvedProperties includes all three tier IDs")
    func agendaEventSchemaIncludesTiers() {
        let schema = AgendaEventSchema.defaultSeed()
        let resolved = schema.resolvedProperties(tierConfig: tierConfig)
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(resolved.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test("AgendaEventSchema stored properties does NOT contain tier IDs")
    func agendaEventSchemaStoredPropertiesExcludesTiers() {
        let schema = AgendaEventSchema.defaultSeed()
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!schema.properties.contains { $0.id == ReservedPropertyID.tier3 })
    }
}
