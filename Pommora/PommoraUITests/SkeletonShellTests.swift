import XCTest

final class SkeletonShellTests: XCTestCase {
    func test_appLaunches_andShowsSearchFieldAndFavoritesSection() throws {
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

        // Middle and detail columns are intentionally empty (no ContentUnavailableView placeholder
        // — that was removed once the skeleton's empty state was finalized). Future features
        // populate them via sidebar selection.
        XCTAssertFalse(app.staticTexts["No selection"].exists,
                       "Middle column should not display the removed 'No selection' placeholder")
        XCTAssertFalse(app.staticTexts["No detail"].exists,
                       "Detail column should not display the removed 'No detail' placeholder")
    }
}
