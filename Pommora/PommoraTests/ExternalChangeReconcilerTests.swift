//
//  ExternalChangeReconcilerTests.swift
//  PommoraTests
//
//  Unit coverage for the reconciler's intake classification — the decision that
//  routes each changed path to the open editor, the surgical reindex, or the
//  coarse rebuild. The regression test pins the moved-open-Page case: a Page whose
//  file is moved or deleted out from under its open editor must force a coarse
//  reconcile (which re-points the editor by stable id), never silently defer to an
//  editor that can't reload a missing file and would re-save it at the old path.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite(.serialized)
struct ExternalChangeReconcilerTests {

    /// `disposition` reads only the URL, the filesystem, and the AppGlobals editor
    /// registry — not Nexus state — so a bare env is enough to exercise it.
    private func makeReconciler(_ nexus: Nexus) -> ExternalChangeReconciler {
        let env = NexusEnvironment(nexus: nexus, nexusManager: NexusManager())
        return ExternalChangeReconciler(env: env, nexusID: nexus.id)
    }

    /// Registers a live editor VM at `url` in the AppGlobals registry (where the
    /// reconciler looks for the open Page). Caller unregisters in a `defer`.
    private func openEditor(at url: URL) -> PageEditorViewModel {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let vm = PageEditorViewModel(
            page: PageMeta(id: fm.id, title: "Note", url: url, frontmatter: fm),
            body: "", saver: NoopPageSaver())
        AppGlobals.register(vm)
        return vm
    }

    @Test("An open Page's in-place external edit defers to the editor")
    func inPlaceEditDefersToEditor() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let pageURL = nexus.rootURL.appendingPathComponent("Note.md")
        try "body".write(to: pageURL, atomically: true, encoding: .utf8)

        let vm = openEditor(at: pageURL)
        defer { AppGlobals.unregister(vm) }

        guard case .deferToEditor = makeReconciler(nexus).disposition(of: pageURL) else {
            Issue.record("an existing open-Page file should defer to its editor for in-place reload")
            return
        }
    }

    @Test("A Page moved out from under its open editor routes to reconcile, not the editor")
    func movedOpenPageRoutesToReconcile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // The editor is open at this path, but the file is GONE — an external move
        // or delete. The old path FSEvents reports no longer exists on disk.
        let goneURL = nexus.rootURL.appendingPathComponent("Note.md")

        let vm = openEditor(at: goneURL)
        defer { AppGlobals.unregister(vm) }

        guard case .reconcile = makeReconciler(nexus).disposition(of: goneURL) else {
            Issue.record(
                "a gone open-Page path must reconcile so the coarse rebuild re-points the editor by id — deferring to an editor that can't reload a missing file leaves it pointed at the old path and re-saves the file there")
            return
        }
    }

    @Test("A gone path in the batch forces the coarse rebuild — surgicalScopes returns nil")
    func gonePathForcesCoarse() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let env = NexusEnvironment(nexus: nexus, nexusManager: NexusManager())
        let reconciler = ExternalChangeReconciler(env: env, nexusID: nexus.id)

        let collectionFolder = try makeCollection(titled: "Notes", in: nexus)
        await env.collectionManager.loadAll()
        let existing = collectionFolder.appendingPathComponent("Kept.md")
        try writePage(at: existing)

        // A batch of purely existing Pages in a known scope is surgical-eligible…
        #expect(reconciler.surgicalScopes(for: [existing], nexus: nexus) != nil)
        // …but one gone path in the same batch drops the whole batch to coarse —
        // the fallback that re-points a moved open editor by stable id.
        let gone = collectionFolder.appendingPathComponent("Moved.md")  // never written
        #expect(reconciler.surgicalScopes(for: [existing, gone], nexus: nexus) == nil)
    }

    // MARK: - Fixtures

    /// Creates a collection (PageCollection) folder + sidecar on disk; returns the folder URL.
    private func makeCollection(titled title: String, in nexus: Nexus) throws -> URL {
        let folder = NexusPaths.collectionFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let collection = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date())
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
        return folder
    }

    /// Writes a real `.md` Page carrying a stable id at `url`.
    private func writePage(at url: URL) throws {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        try PageFile(
            frontmatter: fm, body: "",
            title: url.deletingPathExtension().lastPathComponent
        ).save(to: url)
    }
}

@MainActor
private final class NoopPageSaver: PageSaver {
    func save(page: PageMeta, body: String) async throws {}
}
