import Foundation
import Testing

@testable import Pommora

@Suite("MigrationEvent") struct MigrationEventTests {
    @Test func allThreeCasesAreConstructible() {
        let events: [MigrationEvent] = [
            .relationShapeWrapped(propertyID: "prop_01", entityID: "01HENTITY"),
            .allowsMultipleStripped(propertyID: "prop_02", collectionID: "01HTYPE"),
            .agendaSchemaUnified(collectionID: "_agenda_tasks", propertyCount: 3),
        ]
        #expect(events.count == 3)
    }
}
