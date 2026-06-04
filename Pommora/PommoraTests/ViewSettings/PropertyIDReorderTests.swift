import Testing

@testable import Pommora

@Suite struct PropertyIDReorderTests {
    @Test func movesDownAndUp() {
        let order = ["a", "b", "c", "d"]
        #expect(PropertyIDReorder.move(order, moving: "a", onto: "c") == ["b", "a", "c", "d"])
        #expect(PropertyIDReorder.move(order, moving: "d", onto: "b") == ["a", "d", "b", "c"])
        #expect(PropertyIDReorder.move(order, moving: "a", onto: "a") == order)  // no-op
        #expect(PropertyIDReorder.move(order, moving: "z", onto: "b") == order)  // unknown
    }
}
