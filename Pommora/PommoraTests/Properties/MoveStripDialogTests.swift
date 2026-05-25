import Foundation
import Testing

@testable import Pommora

/// Tests for `MoveStripConfirmationDialog` — the move-strip preview dialog added in Phase J.10.
///
/// SwiftUI rendering is not driven in these tests; callbacks and data presentation
/// are validated via direct construction and callback capture.
@Suite("MoveStripDialogTests")
struct MoveStripDialogTests {

    // MARK: - Callback tracker (reference type avoids inout-capture restrictions)

    final class CallTracker: @unchecked Sendable {
        var moveAndStripCalled = false
        var addPropertyFirstCalled = false
        var cancelCalled = false
    }

    // MARK: - Helpers

    @MainActor
    private func makeDialog(
        stripped: [(name: String, valuePreview: String)] = [],
        tracker: CallTracker = CallTracker()
    ) -> MoveStripConfirmationDialog {
        MoveStripConfirmationDialog(
            entityTitle: "My Page",
            sourceTypeTitle: "Source Type",
            destTypeTitle: "Destination Type",
            strippedProperties: stripped,
            onMoveAndStrip: { tracker.moveAndStripCalled = true },
            onAddPropertyFirst: { tracker.addPropertyFirstCalled = true },
            onCancel: { tracker.cancelCalled = true }
        )
    }

    // MARK: - Test 1: empty stripped list — no strip warning

    @Test("Empty strippedProperties list — strippedProperties is empty")
    @MainActor
    func emptyStrippedListShowsNoWarning() {
        let dialog = makeDialog(stripped: [])
        #expect(dialog.strippedProperties.isEmpty)
    }

    // MARK: - Test 2: non-empty stripped list — all names and previews present

    @Test("Non-empty strippedProperties — all names and value previews are preserved")
    @MainActor
    func nonEmptyStrippedListPreservesData() {
        let props: [(name: String, valuePreview: String)] = [
            (name: "Priority", valuePreview: "3"),
            (name: "Tags",     valuePreview: "research, frontend"),
        ]
        let dialog = makeDialog(stripped: props)
        #expect(dialog.strippedProperties.count == 2)
        let first = dialog.strippedProperties[0]
        #expect(first.name == "Priority")
        #expect(first.valuePreview == "3")
        let second = dialog.strippedProperties[1]
        #expect(second.name == "Tags")
        #expect(second.valuePreview == "research, frontend")
    }

    // MARK: - Test 3: onMoveAndStrip callback fires

    @Test("onMoveAndStrip callback is called when Move and Strip is triggered")
    @MainActor
    func moveAndStripCallbackFires() {
        let tracker = CallTracker()
        let dialog = makeDialog(
            stripped: [(name: "Status", valuePreview: "In Progress")],
            tracker: tracker
        )
        dialog.onMoveAndStrip()
        #expect(tracker.moveAndStripCalled)
        #expect(!tracker.addPropertyFirstCalled)
        #expect(!tracker.cancelCalled)
    }

    // MARK: - Test 4: onAddPropertyFirst callback fires

    @Test("onAddPropertyFirst callback is called when Add Property First is triggered")
    @MainActor
    func addPropertyFirstCallbackFires() {
        let tracker = CallTracker()
        let dialog = makeDialog(
            stripped: [(name: "Status", valuePreview: "Done")],
            tracker: tracker
        )
        dialog.onAddPropertyFirst()
        #expect(tracker.addPropertyFirstCalled)
        #expect(!tracker.moveAndStripCalled)
        #expect(!tracker.cancelCalled)
    }

    // MARK: - Test 5: onCancel callback fires

    @Test("onCancel callback is called when Cancel is triggered")
    @MainActor
    func cancelCallbackFires() {
        let tracker = CallTracker()
        let dialog = makeDialog(stripped: [], tracker: tracker)
        dialog.onCancel()
        #expect(tracker.cancelCalled)
        #expect(!tracker.moveAndStripCalled)
        #expect(!tracker.addPropertyFirstCalled)
    }

    // MARK: - Test 6: heading text encodes entity and type titles

    @Test("Dialog stores entityTitle, sourceTypeTitle, and destTypeTitle correctly")
    @MainActor
    func headingEncodesEntityAndTypes() {
        let dialog = makeDialog(stripped: [])
        #expect(dialog.entityTitle == "My Page")
        #expect(dialog.sourceTypeTitle == "Source Type")
        #expect(dialog.destTypeTitle == "Destination Type")
    }

    // MARK: - Test 7: MoveStripRow id is stable (Identifiable)

    @Test("MoveStripRow is Identifiable with a unique id per instance")
    func moveStripRowIsIdentifiable() {
        let row1 = MoveStripRow(name: "A", valuePreview: "1")
        let row2 = MoveStripRow(name: "A", valuePreview: "1")
        // Same content, different identity (UUID per instance)
        #expect(row1.id != row2.id)
    }
}
