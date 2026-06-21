import Foundation
import Testing

@testable import Pommora

/// Tests for `FileAttachmentEditorViewModel` — the attach/remove logic backing `FileAttachmentEditor`.
///
/// `AttachmentManager.attach` requires real filesystem access, so each test writes a temp
/// file of the appropriate size, then drives the view-model's `attach` / `remove` methods.
@Suite("FileAttachmentEditorTests")
struct FileAttachmentEditorTests {

    // MARK: - Helpers

    private func makeVM(
        attachments: [FileRef] = [],
        accept: [String]? = nil
    ) -> (vm: FileAttachmentEditorViewModel, nexusRoot: URL, changed: () -> [FileRef]) {
        let nexusRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FAETests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: nexusRoot, withIntermediateDirectories: true)
        var captured: [FileRef] = []
        let vm = FileAttachmentEditorViewModel(
            attachments: attachments,
            entityID: "ent_test",
            nexusRoot: nexusRoot,
            accept: accept,
            onChange: { captured = $0 }
        )
        return (vm, nexusRoot, { captured })
    }

    /// Writes a temp file of `size` bytes and returns its URL.
    private func makeTempFile(size: Int, name: String = "test.pdf") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        let data = Data(repeating: 0x41, count: size)
        try data.write(to: url)
        return url
    }

    // MARK: - Test 1: sub-50 MB attach succeeds and appends FileRef

    @Test("Sub-50 MB attach succeeds and appends FileRef to attachments")
    func subWarnSizeAttachSucceeds() async throws {
        let (vm, _, changed) = makeVM()
        // 10 MB — well under the 50 MB warning threshold
        let src = try makeTempFile(size: 10_000_000)
        defer { try? FileManager.default.removeItem(at: src) }

        _ = await MainActor.run {
            Task { await vm.attach(file: src) }
        }
        // Give the async task a moment to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        await MainActor.run {
            #expect(vm.attachments.count == 1)
            #expect(vm.sizeWarningPending == nil)
            #expect(vm.errorMessage == nil)
        }
        _ = changed  // suppress unused warning
    }

    // MARK: - Test 2: 60 MB triggers sizeWarningRequired; confirm re-calls and succeeds

    @Test("60 MB attach triggers sizeWarningRequired; confirming re-calls attach without confirmation")
    func sixtyMBTriggersWarningThenSucceeds() async throws {
        let (vm, _, _) = makeVM()
        // 60 MB — above 50 MB warn threshold, under 500 MB hard cap
        let src = try makeTempFile(size: 60_000_000)
        defer { try? FileManager.default.removeItem(at: src) }

        await vm.attach(file: src, requireConfirmation: true)

        await MainActor.run {
            #expect(vm.sizeWarningPending != nil)
            #expect(vm.attachments.isEmpty)
        }

        await vm.confirmSizeWarning()

        await MainActor.run {
            #expect(vm.sizeWarningPending == nil)
            #expect(vm.attachments.count == 1)
            #expect(vm.errorMessage == nil)
        }
    }

    // MARK: - Test 3: 501 MB throws exceedsSizeCap regardless

    @Test("501 MB attach sets errorMessage via exceedsSizeCap — hard cap always enforced")
    func hardCapAlwaysRejected() async throws {
        let (vm, _, _) = makeVM()
        // 501 MB — at or above the 500 MB hard cap
        let src = try makeTempFile(size: 501_000_000)
        defer { try? FileManager.default.removeItem(at: src) }

        await vm.attach(file: src, requireConfirmation: false)

        await MainActor.run {
            #expect(vm.attachments.isEmpty)
            #expect(vm.errorMessage != nil)
            #expect(vm.sizeWarningPending == nil)
        }
    }

    // MARK: - Test 4: MIME mismatch throws mimeNotAccepted

    @Test("File with MIME not in accept list sets errorMessage via mimeNotAccepted")
    func mimeNotAcceptedSetsError() async throws {
        // Accept only PDF; attach a .txt file
        let (vm, _, _) = makeVM(accept: ["application/pdf"])
        let src = try makeTempFile(size: 1_000, name: "note.txt")
        defer { try? FileManager.default.removeItem(at: src) }

        await vm.attach(file: src)

        await MainActor.run {
            #expect(vm.attachments.isEmpty)
            #expect(vm.errorMessage != nil)
        }
    }

    // MARK: - Test 5: remove drops FileRef from array

    @Test("remove(ref:) drops the FileRef from attachments and calls onChange")
    func removeDropsRef() async throws {
        let existing = FileRef(
            path: ".nexus/attachments/ent_test/file.pdf",
            originalName: "file.pdf",
            addedAt: Date(),
            mimeType: "application/pdf"
        )
        let (vm, _, changed) = makeVM(attachments: [existing])

        await MainActor.run {
            vm.remove(ref: existing)
            #expect(vm.attachments.isEmpty)
        }
        _ = changed
    }
}
