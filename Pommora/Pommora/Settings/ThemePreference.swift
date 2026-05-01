import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case device
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .device: return "Match Device"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .device: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
