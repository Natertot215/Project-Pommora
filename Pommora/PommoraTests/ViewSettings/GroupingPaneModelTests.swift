import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("GroupingPaneModelTests")
struct GroupingPaneModelTests {

    // MARK: - init

    @Test("init with .property sets groupingEnabled and exposes grouping")
    func initWithProperty() {
        let g = PropertyGrouping(propertyID: "prop_status")
        let m = GroupingPaneModel(config: .property(g)) { _ in }
        #expect(m.groupingEnabled == true)
        #expect(m.grouping?.propertyID == "prop_status")
    }

    @Test("init with .structural sets groupingEnabled false and grouping nil")
    func initWithStructural() {
        let m = GroupingPaneModel(config: .structural) { _ in }
        #expect(m.groupingEnabled == false)
        #expect(m.grouping == nil)
    }

    // MARK: - setGroupingEnabled

    @Test("ON with remembered property restores .property and fires onSave")
    func toggleOnWithRemembered() {
        var saved: [GroupConfig] = []
        let m = GroupingPaneModel(config: .structural) { saved.append($0) }
        // establish a remembered property via selectProperty then toggle off
        m.selectProperty("prop_priority")
        saved.removeAll()
        m.setGroupingEnabled(false)
        saved.removeAll()
        // now toggle back on — should restore
        m.setGroupingEnabled(true)
        #expect(m.groupingEnabled == true)
        if case .property(let g) = m.config {
            #expect(g.propertyID == "prop_priority")
        } else {
            Issue.record("Expected .property config after ON with remembered")
        }
        #expect(saved.count == 1)
        if case .property(let g) = saved.first {
            #expect(g.propertyID == "prop_priority")
        } else {
            Issue.record("onSave not called with .property config")
        }
    }

    @Test("ON with nothing remembered leaves config .structural and does not fire onSave")
    func toggleOnWithNoRemembered() {
        var saved: [GroupConfig] = []
        let m = GroupingPaneModel(config: .structural) { saved.append($0) }
        m.setGroupingEnabled(true)
        #expect(m.groupingEnabled == true)
        #expect(m.config == .structural)
        // onSave must NOT have been called with a .property config
        let propertyCalls = saved.filter {
            if case .property = $0 { return true }
            return false
        }
        #expect(propertyCalls.isEmpty)
    }

    @Test("OFF reverts to .structural and fires onSave")
    func toggleOffReverts() {
        var saved: [GroupConfig] = []
        let g = PropertyGrouping(propertyID: "prop_tag")
        let m = GroupingPaneModel(config: .property(g)) { saved.append($0) }
        saved.removeAll()
        m.setGroupingEnabled(false)
        #expect(m.config == .structural)
        #expect(saved.count == 1)
        #expect(saved.first == .structural)
    }

    // MARK: - selectProperty

    @Test("selectProperty sets .property config and fires onSave")
    func selectPropertyFresh() {
        var saved: [GroupConfig] = []
        let m = GroupingPaneModel(config: .structural) { saved.append($0) }
        m.selectProperty("p")
        if case .property(let g) = m.config {
            #expect(g.propertyID == "p")
        } else {
            Issue.record("Expected .property config after selectProperty")
        }
        #expect(saved.count == 1)
        if case .property(let g) = saved.first {
            #expect(g.propertyID == "p")
        } else {
            Issue.record("onSave not called with .property config")
        }
    }

    // MARK: - update

    @Test("update orderMode persists and fires onSave")
    func updateOrderMode() {
        var saved: [GroupConfig] = []
        let g = PropertyGrouping(propertyID: "prop_select")
        let m = GroupingPaneModel(config: .property(g)) { saved.append($0) }
        saved.removeAll()
        m.update { $0.orderMode = .reversed }
        #expect(m.grouping?.orderMode == .reversed)
        #expect(saved.count == 1)
        if case .property(let sg) = saved.first {
            #expect(sg.orderMode == .reversed)
        } else {
            Issue.record("onSave not called with updated config")
        }
    }

    @Test("update order + orderMode persists both")
    func updateOrderAndMode() {
        var saved: [GroupConfig] = []
        let g = PropertyGrouping(propertyID: "prop_select")
        let m = GroupingPaneModel(config: .property(g)) { saved.append($0) }
        saved.removeAll()
        m.update { $0.order = ["a"]; $0.orderMode = .manual }
        #expect(m.grouping?.order == ["a"])
        #expect(m.grouping?.orderMode == .manual)
        #expect(saved.count == 1)
    }

    @Test("update hideEmptyGroups + emptyPlacement persists both")
    func updateEmptyControls() {
        var saved: [GroupConfig] = []
        let g = PropertyGrouping(propertyID: "prop_status")
        let m = GroupingPaneModel(config: .property(g)) { saved.append($0) }
        saved.removeAll()
        m.update { $0.hideEmptyGroups = true; $0.emptyPlacement = .top }
        #expect(m.grouping?.hideEmptyGroups == true)
        #expect(m.grouping?.emptyPlacement == .top)
        #expect(saved.count == 1)
    }

    // MARK: - remembered survives OFF

    @Test("OFF then ON restores the remembered property")
    func offThenOnRestores() {
        var saved: [GroupConfig] = []
        let m = GroupingPaneModel(config: .structural) { saved.append($0) }
        m.selectProperty("prop_owner")
        m.setGroupingEnabled(false)
        saved.removeAll()
        m.setGroupingEnabled(true)
        if case .property(let g) = m.config {
            #expect(g.propertyID == "prop_owner")
        } else {
            Issue.record("Expected .property after OFF then ON")
        }
        #expect(saved.count == 1)
    }
}
