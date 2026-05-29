import Foundation
import Testing
@testable import Pommora

/// Covers the shared consent predicate that gates the adoption-preview modal:
/// `PropertyIDMigration.Plan.requiresAcknowledgment` (true only for lossy
/// changes — today, dropping a context-tier-targeted relation property) plus
/// the `contextTierDropCountsByTier` accessor the preview uses to summarize
/// drops without rendering raw IDs. Pure value-type seam — the `@State`-driven
/// button-disabled state in AdoptionPreviewView is not unit-testable here.
@Suite("MigrationConsent") struct MigrationConsentTests {

    /// Builds a TypeMigration carrying the supplied events, with otherwise
    /// inert fields, so a Plan can be assembled directly in-memory.
    private func pageTypeMigration(events: [MigrationEvent]) -> PropertyIDMigration.TypeMigration {
        PropertyIDMigration.TypeMigration(
            kind: .pageType,
            typeFolderURL: URL(fileURLWithPath: "/tmp/Type"),
            typeTitle: "Type",
            sidecarURL: URL(fileURLWithPath: "/tmp/Type/_pagetype.json"),
            propertiesToMint: 0,
            memberFileCandidates: 0,
            nameToID: [:],
            updatedSchemaJSON: Data(),
            events: events
        )
    }

    private func plan(events: [MigrationEvent]) -> PropertyIDMigration.Plan {
        var plan = PropertyIDMigration.Plan.empty(at: URL(fileURLWithPath: "/tmp/Nexus"))
        plan.pageTypeMigrations = [pageTypeMigration(events: events)]
        return plan
    }

    @Test func lossyDropRequiresAcknowledgment() {
        let p = plan(events: [
            .contextTierDropped(propertyID: "prop_01", tier: 1, typeID: "01HTYPE"),
            .contextTierDropped(propertyID: "prop_02", tier: 1, typeID: "01HTYPE"),
            .contextTierDropped(propertyID: "prop_03", tier: 3, typeID: "01HTYPE"),
        ])

        #expect(p.requiresAcknowledgment == true)
        #expect(p.contextTierDropCountsByTier == [1: 2, 3: 1])
    }

    @Test func losslessOnlyDoesNotRequireAcknowledgment() {
        let p = plan(events: [
            .pageCollectionRewritten(propertyID: "prop_04", from: "01HCOLL", to: "01HTYPE")
        ])

        #expect(p.requiresAcknowledgment == false)
        #expect(p.contextTierDropCountsByTier.isEmpty)
    }

    @Test func emptyPlanDoesNotRequireAcknowledgment() {
        let p = PropertyIDMigration.Plan.empty(at: URL(fileURLWithPath: "/tmp/Nexus"))

        #expect(p.requiresAcknowledgment == false)
        #expect(p.contextTierDropCountsByTier.isEmpty)
    }
}
