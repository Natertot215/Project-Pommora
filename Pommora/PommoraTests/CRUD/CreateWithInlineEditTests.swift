import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("CreateWithInlineEdit")
struct CreateWithInlineEditTests {

    /// Lightweight stand-in for a created entity (ULID-string id, matches every
    /// real Pommora entity's `Identifiable` shape).
    private struct Stub: Identifiable, Equatable {
        let id: String
    }

    @Test("on success, onCreate is called with the entity returned by create")
    func onCreateInvokedWithEntity() async throws {
        var captured: Stub?
        let result = try await CreateWithInlineEdit.run(
            create: { Stub(id: "stub_001") },
            onCreate: { captured = $0 }
        )
        #expect(result == Stub(id: "stub_001"))
        #expect(captured == Stub(id: "stub_001"))
    }

    @Test("on failure, onCreate is NOT called and the error propagates")
    func failureSkipsOnCreate() async {
        struct Boom: Error {}
        var called = false
        await #expect(throws: Boom.self) {
            _ = try await CreateWithInlineEdit.run(
                create: { () async throws -> Stub in throw Boom() },
                onCreate: { _ in called = true }
            )
        }
        #expect(called == false)
    }

    @Test("onCreate fires strictly AFTER create resolves")
    func ordering() async throws {
        // Capture the order in which the two closures run by appending markers
        // to a shared array. The expected order is ["created", "onCreate"] —
        // onCreate must never run before create finishes producing the entity.
        var events: [String] = []
        _ = try await CreateWithInlineEdit.run(
            create: { () async throws -> Stub in
                events.append("created")
                return Stub(id: "x")
            },
            onCreate: { _ in events.append("onCreate") }
        )
        #expect(events == ["created", "onCreate"])
    }
}
