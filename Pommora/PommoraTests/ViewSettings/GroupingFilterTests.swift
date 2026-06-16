import Foundation
import Testing
@testable import Pommora

/// Asserts that `isGroupable` includes `.date`/`.datetime` and still excludes
/// `.multiSelect` and `.relation`. Exercises the private helper directly via
/// `@testable import` after it was relaxed to `internal`.
@Suite("GroupingFilterTests") struct GroupingFilterTests {
    @Test("date and datetime are groupable")
    func dateTypesAreGroupable() {
        #expect(ViewSettingsProperties.isGroupable(.date) == true)
        #expect(ViewSettingsProperties.isGroupable(.datetime) == true)
    }

    @Test("multiSelect is not groupable")
    func multiSelectIsNotGroupable() {
        #expect(ViewSettingsProperties.isGroupable(.multiSelect) == false)
    }

    @Test("relation is not groupable")
    func relationIsNotGroupable() {
        #expect(ViewSettingsProperties.isGroupable(.relation) == false)
    }

    @Test("existing groupable types remain groupable")
    func existingGroupableTypes() {
        #expect(ViewSettingsProperties.isGroupable(.select) == true)
        #expect(ViewSettingsProperties.isGroupable(.status) == true)
        #expect(ViewSettingsProperties.isGroupable(.checkbox) == true)
    }
}
