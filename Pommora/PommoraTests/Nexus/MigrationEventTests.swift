import Foundation
import Testing
@testable import Pommora

@Suite("MigrationEvent") struct MigrationEventTests {
    @Test func allSixCasesAreConstructible() {
        let events: [MigrationEvent] = [
            .relationShapeWrapped(propertyID: "prop_01", entityID: "01HENTITY"),
            .allowsMultipleStripped(propertyID: "prop_02", typeID: "01HTYPE"),
            .pageCollectionRewritten(propertyID: "prop_03", from: "01HCOLL", to: "01HTYPE"),
            .itemCollectionRewritten(propertyID: "prop_04", from: "01HCOLL", to: "01HTYPE"),
            .contextTierDropped(propertyID: "prop_05", tier: 1, typeID: "01HTYPE"),
            .agendaSchemaUnified(typeID: "_agenda_tasks", propertyCount: 3),
        ]
        #expect(events.count == 6)
    }
}
