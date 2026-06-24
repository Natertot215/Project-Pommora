import Foundation
import Testing
@testable import Pommora

@Suite("ReservedTypeID") struct ReservedTypeIDTests {
    @Test func agendaTasksConstantMatchesExpectedRawValue() {
        #expect(ReservedTypeID.agendaTasks == "_agenda_tasks")
    }

    @Test func agendaEventsConstantMatchesExpectedRawValue() {
        #expect(ReservedTypeID.agendaEvents == "_agenda_events")
    }
}
