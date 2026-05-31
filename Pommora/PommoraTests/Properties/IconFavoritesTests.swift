import Foundation
import Testing

@testable import Pommora

/// Outcome tests for the pure Saved-icon ordering/cap logic + the UserDefaults
/// round-trip. Struct name matches the filename so `-only-testing:PommoraTests/
/// IconFavoritesTests` actually runs it (quirk #17).
@Suite struct IconFavoritesTests {

    /// An isolated, empty UserDefaults suite per test so persistence tests don't
    /// touch the real app domain or each other.
    private func isolatedDefaults(_ fn: String = #function) -> UserDefaults {
        let suite = "test.iconfavorites.\(fn)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func togglingAbsentNamePrependsIt() {
        #expect(IconFavorites.toggled("star", in: ["heart", "flag"]) == ["star", "heart", "flag"])
    }

    @Test func togglingPresentNameRemovesIt() {
        #expect(IconFavorites.toggled("heart", in: ["star", "heart", "flag"]) == ["star", "flag"])
    }

    @Test func newestSavedComesFirst() {
        var saved: [String] = []
        saved = IconFavorites.toggled("a", in: saved)
        saved = IconFavorites.toggled("b", in: saved)
        #expect(saved == ["b", "a"])
    }

    @Test func togglingPresentThenReAddingReturnsItToFront() {
        let removed = IconFavorites.toggled("star", in: ["star", "heart"])
        #expect(removed == ["heart"])
        #expect(IconFavorites.toggled("star", in: removed) == ["star", "heart"])
    }

    @Test func capDropsOldestWhenExceeded() {
        let full = (0..<IconFavorites.cap).map { "s\($0)" }  // exactly `cap` items
        let result = IconFavorites.toggled("new", in: full)
        #expect(result.count == IconFavorites.cap)
        #expect(result.first == "new")
        #expect(result.last != full.last)  // oldest pushed off the end
    }

    @Test func persistRoundTrips() {
        let defaults = isolatedDefaults()
        IconFavorites.persist(["star", "flag"], to: defaults)
        #expect(IconFavorites.load(defaults) == ["star", "flag"])
    }

    @Test func loadDefaultsToEmpty() {
        #expect(IconFavorites.load(isolatedDefaults()) == [])
    }
}
