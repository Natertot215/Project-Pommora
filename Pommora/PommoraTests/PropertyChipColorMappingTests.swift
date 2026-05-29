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

    @Test func tealAndIndigoPersistDirectly() {
        // Fix Log #9: teal/indigo are now first-class persisted SelectColors,
        // not collapsed to blue/purple on save.
        #expect(PropertyChipColor.teal.toSelectColor() == .teal)
        #expect(PropertyChipColor.indigo.toSelectColor() == .indigo)
        // Round-trips back to the same UI color.
        #expect(PropertyChipColor(selectColor: .teal) == .teal)
        #expect(PropertyChipColor(selectColor: .indigo) == .indigo)
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
