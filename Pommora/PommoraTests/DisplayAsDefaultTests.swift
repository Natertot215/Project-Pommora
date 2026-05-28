//
//  DisplayAsDefaultTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

struct DisplayAsDefaultTests {
    // The editor treats nil displayAs as .select and writes nil for "Select".
    // The cell MUST resolve nil the same way, else the pill is unreachable.
    @Test func nilDisplayAsResolvesToSelect() {
        let def = PropertyDefinition(id: "s", name: "Status", type: .status)
        #expect((def.displayAs ?? .select) == .select)
    }
}
