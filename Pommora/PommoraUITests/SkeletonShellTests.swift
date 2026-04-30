import XCTest

final class SkeletonShellTests: XCTestCase {
    func test_appLaunches_andShowsSearchFieldAndPlaceholder() throws {
        let app = XCUIApplication()
        app.launch()

        // Sidebar search field is visible.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Sidebar search field should exist")

        // Sidebar shows only the Favorites placeholder section header — no Folders/Files/Tags/Recents.
        XCTAssertTrue(app.staticTexts["Favorites"].exists,
                      "Sidebar should show Favorites section")
        XCTAssertFalse(app.staticTexts["Folders"].exists,
                       "Sidebar should NOT show Folders section in skeleton")
        XCTAssertFalse(app.staticTexts["Files"].exists,
                       "Sidebar should NOT show Files section in skeleton")
        XCTAssertFalse(app.staticTexts["Tags"].exists,
                       "Sidebar should NOT show Tags section in skeleton")
        XCTAssertFalse(app.staticTexts["Recents"].exists,
                       "Sidebar should NOT show Recents row in skeleton")

        // Middle column shows the empty-state placeholder.
        XCTAssertTrue(app.staticTexts["No selection"].exists
                      || app.staticTexts["Select an item"].exists,
                      "Middle column should show ContentUnavailableView placeholder")
    }
}
