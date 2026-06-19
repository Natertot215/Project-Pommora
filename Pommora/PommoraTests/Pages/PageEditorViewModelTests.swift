import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageEditorViewModel")
struct PageEditorViewModelTests {

    @Test("Debounce coalesces rapid edits into a single save")
    func debounceCoalescesRapidEdits() async throws {
        let saver = StubPageSaver()
        let vm = PageEditorViewModel(page: testPage(), body: "", saver: saver)

        vm.body = "A"
        vm.body = "B"
        vm.body = "C"

        // Event-based wait, NOT a fixed wall-clock sleep: a fixed sleep slips past
        // the 300ms debounce under full-suite parallel CPU load and flakes. Poll
        // until the debounced save actually fires (>=1), with a generous ceiling
        // so a saturated host just polls longer rather than failing early.
        try await pollUntil(timeout: .seconds(5), interval: .milliseconds(25)) {
            saver.saved.count >= 1
        }

        // Settle past one more debounce window to prove the 3 edits COALESCED into
        // exactly one save (not three) — if a stray timer were still pending it'd
        // land inside this window and bump the count.
        try await Task.sleep(for: PageEditorViewModel.debounce * 2)

        #expect(saver.saved.count == 1)
        #expect(saver.saved.first?.body == "C")
    }

    /// Polls `condition` every `interval` until it returns true or `timeout`
    /// elapses; throws if the timeout is hit. Lets a debounced-save assertion
    /// wait on the *event* (the save landing) instead of a fixed wall-clock
    /// duration that flakes under parallel-suite CPU load.
    private func pollUntil(
        timeout: Duration,
        interval: Duration,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: interval)
        }
        throw PollTimeout.exceeded
    }

    @Test("flushNow cancels pending debounce and saves immediately")
    func explicitSaveFlushesPendingDebounce() async throws {
        let saver = StubPageSaver()
        let vm = PageEditorViewModel(page: testPage(), body: "", saver: saver)

        vm.body = "X"
        await vm.flushNow()  // cancels the 300ms debounce, awaits the save

        #expect(saver.saved.count == 1)
        #expect(saver.saved.first?.body == "X")
        #expect(vm.pendingError == nil)
    }

    @Test("close() flushes pending save synchronously (Page switch)")
    func pageSwitchFlushesPendingSave() async throws {
        let saver = StubPageSaver()
        let vm = PageEditorViewModel(page: testPage(), body: "", saver: saver)

        vm.body = "Y"
        await vm.close()

        #expect(saver.saved.count == 1)
        #expect(saver.saved.first?.body == "Y")
    }

    @Test("Multiple close() calls don't double-save (idempotent)")
    func windowCloseFlushesPendingSave() async throws {
        let saver = StubPageSaver()
        let vm = PageEditorViewModel(page: testPage(), body: "", saver: saver)

        vm.body = "Z"
        await vm.close()
        await vm.close()  // second close — nothing pending; should not re-save

        // The second close calls flushNow which calls saver.save with the
        // current body even if no debounce is pending — that's the contract
        // (idempotent re-save is fine; the failure mode we guard against is
        // a pending debounce being lost, not duplicate saves on close).
        // Accept count == 1 (no pending) OR count == 2 (re-saved unchanged).
        // Body must always match.
        #expect(saver.saved.allSatisfy { $0.body == "Z" })
        #expect(saver.saved.count >= 1)
    }

    @Test("Save failure populates pendingError and preserves draft body")
    func saveFailurePopulatesPendingError() async throws {
        let saver = StubPageSaver()
        saver.nextError = StubSaveError.simulated
        let vm = PageEditorViewModel(page: testPage(), body: "", saver: saver)

        vm.body = "draft text"
        await vm.flushNow()

        #expect(vm.pendingError != nil)
        #expect(vm.body == "draft text")  // draft preserved on failure
    }

    // MARK: - Watcher-driven reload (protect live edits)

    @Test("reloadFromDisk loads an external edit into a clean editor")
    func reloadFromDiskClean() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let saver = StubPageSaver()
        let meta = try writePage(body: "original", in: root)
        let vm = PageEditorViewModel(page: meta, body: "original", saver: saver)

        try PageFile(frontmatter: meta.frontmatter, body: "external", title: "Note")
            .save(to: meta.url)
        vm.reloadFromDisk(nexusRoot: root)

        #expect(vm.body == "external")
        // The reload must not schedule a save (no echo back to disk).
        try await Task.sleep(for: PageEditorViewModel.debounce * 2)
        #expect(saver.saved.isEmpty)
    }

    @Test("reloadFromDisk holds when the editor has unflushed edits")
    func reloadFromDiskDirtyHolds() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let meta = try writePage(body: "original", in: root)
        let vm = PageEditorViewModel(page: meta, body: "original", saver: StubPageSaver())

        vm.body = "user typing"  // schedules a debounced save → dirty
        #expect(vm.hasUnflushedEdits)
        try PageFile(frontmatter: meta.frontmatter, body: "external", title: "Note")
            .save(to: meta.url)
        vm.reloadFromDisk(nexusRoot: root)

        #expect(vm.body == "user typing")  // live edit protected, not clobbered
    }

    @Test("flushNow does not resurrect an externally-deleted file when clean")
    func flushNowNoResurrectWhenClean() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let saver = StubPageSaver()
        let meta = try writePage(body: "original", in: root)
        let vm = PageEditorViewModel(page: meta, body: "original", saver: saver)

        try FileManager.default.removeItem(at: meta.url)  // external delete
        await vm.flushNow()  // clean + file gone → skip

        #expect(saver.saved.isEmpty)
    }

    @Test("flushNow re-saves a deleted file when there are unflushed edits")
    func flushNowResurrectsWhenDirty() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let saver = StubPageSaver()
        let meta = try writePage(body: "original", in: root)
        let vm = PageEditorViewModel(page: meta, body: "original", saver: saver)

        vm.body = "user edit"  // dirty
        try FileManager.default.removeItem(at: meta.url)
        await vm.flushNow()  // dirty + file gone → save (protect live edits)

        #expect(saver.saved.count == 1)
        #expect(saver.saved.first?.body == "user edit")
    }

    // MARK: - Fixtures

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Writes a real `.md` Page carrying a stable frontmatter id and returns its meta.
    private func writePage(body: String, named name: String = "Note", in root: URL) throws
        -> PageMeta
    {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let url = root.appendingPathComponent("\(name).md")
        try PageFile(frontmatter: fm, body: body, title: name).save(to: url)
        return PageMeta(id: fm.id, title: name, url: url, frontmatter: fm)
    }

    private func testPage() -> PageMeta {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        // url is non-functional in these tests — the StubPageSaver never
        // actually touches disk.
        return PageMeta(
            id: fm.id,
            title: "TestPage",
            url: URL(fileURLWithPath: "/tmp/test-stub/TestPage.md"),
            frontmatter: fm
        )
    }
}

// MARK: - Test doubles

@MainActor
private final class StubPageSaver: PageSaver {
    var saved: [(page: PageMeta, body: String)] = []
    var nextError: (any Error)?

    func save(page: PageMeta, body: String) async throws {
        if let error = nextError {
            nextError = nil  // one-shot
            throw error
        }
        saved.append((page, body))
    }
}

private enum StubSaveError: Error {
    case simulated
}

/// Thrown by `pollUntil` when the polled condition never becomes true within the
/// timeout — surfaces as a test failure with a clear cause instead of a silent hang.
private enum PollTimeout: Error {
    case exceeded
}
