import SwiftUI
import XCTest
@testable import Pommora

final class ThemePreferenceTests: XCTestCase {
    func test_colorScheme_device_isNil() {
        XCTAssertNil(ThemePreference.device.colorScheme)
    }

    func test_colorScheme_light_isLight() {
        XCTAssertEqual(ThemePreference.light.colorScheme, .light)
    }

    func test_colorScheme_dark_isDark() {
        XCTAssertEqual(ThemePreference.dark.colorScheme, .dark)
    }

    func test_rawValue_isStable() {
        XCTAssertEqual(ThemePreference.device.rawValue, "device")
        XCTAssertEqual(ThemePreference.light.rawValue, "light")
        XCTAssertEqual(ThemePreference.dark.rawValue, "dark")
    }
}
