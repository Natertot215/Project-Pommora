//
//  PropertyChipColorMappingTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

struct PropertyChipColorMappingTests {
    @Test func nilSelectColorMapsToDefault() {
        #expect(PropertyChipColor(selectColor: nil) == .default)
    }

    @Test func defaultAndAccentMapBackToNil() {
        #expect(PropertyChipColor.default.toSelectColor() == nil)
        #expect(PropertyChipColor.accent.toSelectColor() == nil)
    }

    @Test func tealAndIndigoFallBackToNearestPersisted() {
        #expect(PropertyChipColor.teal.toSelectColor() == .blue)
        #expect(PropertyChipColor.indigo.toSelectColor() == .purple)
    }

    @Test func selectOptionMapsToChipOption() {
        let opt = PropertyDefinition.SelectOption(value: "p", label: "Personal", color: .blue)
        let chip = opt.asChipOption()
        #expect(chip.id == "p")
        #expect(chip.label == "Personal")
        #expect(chip.color == .blue)
    }

    @Test func statusOptionInheritsGroupColorWhenUnset() {
        let opt = PropertyDefinition.StatusOption(value: "ns", label: "Not started", color: nil, groupID: .upcoming)
        let chip = opt.asChipOption(groupColor: .green)
        #expect(chip.color == .green)
    }
}
