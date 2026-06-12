import Foundation
import Testing

@testable import Pommora

/// Covers `TableSelectionModel`'s pure selection / range / move math — the
/// row-selection core the native `Table` gave for free. No SwiftUI: every test
/// seeds a flattened `order` and asserts the resulting `selection` / `anchor`.
@Suite("TableSelectionModelTests")
@MainActor
struct TableSelectionModelTests {

    private func model(_ order: [String] = ["a", "b", "c", "d", "e"]) -> TableSelectionModel {
        let m = TableSelectionModel()
        m.order = order
        return m
    }

    // MARK: - Click: plain

    @Test func plainClickReplacesSelectionAndSetsAnchor() {
        let m = model()
        m.click("c", kind: .plain)
        #expect(m.selection == ["c"])
        #expect(m.anchor == "c")

        m.click("a", kind: .plain)
        #expect(m.selection == ["a"])
        #expect(m.anchor == "a")
    }

    // MARK: - Click: toggle (⌘)

    @Test func toggleAddsThenRemoves() {
        let m = model()
        m.click("a", kind: .plain)
        m.click("c", kind: .toggle)
        #expect(m.selection == ["a", "c"])
        #expect(m.anchor == "c")

        m.click("c", kind: .toggle)
        #expect(m.selection == ["a"])
        #expect(m.anchor == "c")
    }

    // MARK: - Click: range (⇧)

    @Test func shiftRangeSpansAnchorToClickInclusive() {
        let m = model()
        m.click("b", kind: .plain)
        m.click("d", kind: .range)
        #expect(m.selection == ["b", "c", "d"])
        // Anchor stays put so a re-span works off the original pivot.
        #expect(m.anchor == "b")
    }

    @Test func shiftRangeWorksBackwards() {
        let m = model()
        m.click("d", kind: .plain)
        m.click("a", kind: .range)
        #expect(m.selection == ["a", "b", "c", "d"])
        #expect(m.anchor == "d")
    }

    @Test func shiftRangeRespansFromOriginalAnchor() {
        let m = model()
        m.click("b", kind: .plain)
        m.click("e", kind: .range)
        #expect(m.selection == ["b", "c", "d", "e"])
        // Shrink the range — still anchored at "b".
        m.click("c", kind: .range)
        #expect(m.selection == ["b", "c"])
    }

    @Test func shiftRangeWithoutAnchorSelectsJustThatID() {
        let m = model()
        m.click("c", kind: .range)
        #expect(m.selection == ["c"])
    }

    // MARK: - Keyboard move

    @Test func moveDownCollapsesToNextRow() {
        let m = model()
        m.click("b", kind: .plain)
        let moved = m.move(.down, extend: false)
        #expect(moved == "c")
        #expect(m.selection == ["c"])
        #expect(m.anchor == "c")
    }

    @Test func moveUpFromTopStaysAtFirst() {
        let m = model()
        m.click("a", kind: .plain)
        let moved = m.move(.up, extend: false)
        #expect(moved == "a")
        #expect(m.selection == ["a"])
    }

    @Test func moveExtendGrowsRangeFromAnchor() {
        let m = model()
        m.click("b", kind: .plain)
        m.move(.down, extend: true)
        #expect(m.selection == ["b", "c"])
        #expect(m.anchor == "b")
    }

    @Test func moveOnEmptyOrderReturnsNil() {
        let m = model([])
        #expect(m.move(.down, extend: false) == nil)
    }

    @Test func moveWithoutAnchorStartsAtEdge() {
        let down = model()
        #expect(down.move(.down, extend: false) == "a")
        let up = model()
        #expect(up.move(.up, extend: false) == "e")
    }

    // MARK: - Type-select

    @Test func typeSelectFindsFirstPrefixMatch() {
        let m = model(["alpha", "apricot", "beta"])
        let titles = ["alpha": "Alpha", "apricot": "Apricot", "beta": "Beta"]
        let target = m.typeSelectTarget(prefix: "ap") { titles[$0] }
        #expect(target == "apricot")
    }

    @Test func typeSelectIsCaseInsensitiveAndPrefixOnly() {
        let m = model(["x", "y"])
        let titles = ["x": "Report", "y": "Roadmap"]
        #expect(m.typeSelectTarget(prefix: "ROAD") { titles[$0] } == "y")
        #expect(m.typeSelectTarget(prefix: "oad") { titles[$0] } == nil)
    }

    @Test func typeSelectEmptyPrefixReturnsNil() {
        let m = model()
        #expect(m.typeSelectTarget(prefix: "") { _ in "anything" } == nil)
    }

    // MARK: - Open target

    @Test func openTargetPrefersAnchorWhenSelected() {
        let m = model()
        m.click("b", kind: .plain)
        m.click("d", kind: .range)
        #expect(m.openTargetID == "b")
    }

    @Test func openTargetFallsBackToFirstSelectedInOrder() {
        let m = model()
        m.click("c", kind: .plain)
        m.click("e", kind: .toggle)
        m.click("c", kind: .toggle)  // removes "c"; anchor now "c" (unselected)
        #expect(m.openTargetID == "e")
    }
}
