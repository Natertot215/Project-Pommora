import Foundation
import MarkdownEngine
import Observation

/// Owns the editable body of a Page. Debounces writes to disk (300ms),
/// flushes on context loss (page switch, window close, app background),
/// surfaces save failures via `pendingError`.
///
/// Frontmatter preservation: this VM binds only to `body`. The editor never
/// sees or edits frontmatter. On save, the existing PageMeta.frontmatter is
/// re-serialized verbatim alongside the new body via PageFile, so frontmatter
/// fields (id, icon, tier1/2/3, properties, createdAt) round-trip faithfully.
@MainActor
@Observable
final class PageEditorViewModel {
    /// The Page being edited. Carries the URL the editor writes back to and
    /// the frontmatter that gets preserved on every save. Mutable so the view
    /// can update it after a successful rename (title + url both change; id
    /// stays). Mutation should ONLY happen with a freshly-resolved PageMeta
    /// from ContentManager — never with a hand-mutated copy.
    var page: PageMeta

    /// Editable body. Every keystroke updates this; `didSet` schedules a
    /// debounced save 300ms from now. Multiple rapid edits coalesce.
    var body: String {
        didSet { scheduleSave() }
    }

    /// UI-only fold state: which heading source lines (e.g. `"## Foo"`) are
    /// currently collapsed in the editor. The set is the convenient handle;
    /// the canonical store is `page.frontmatter.foldedHeadings` (sorted array,
    /// nil-on-empty). Mutations propagate to the frontmatter AND schedule a
    /// save, mirroring the body path — without this, fold-only toggles would
    /// never hit disk because there's no body change.
    var foldedHeadings: Set<String> {
        didSet {
            let asArray = foldedHeadings.isEmpty ? nil : foldedHeadings.sorted()
            guard page.frontmatter.foldedHeadings != asArray else { return }
            page.frontmatter.foldedHeadings = asArray
            scheduleSave()
        }
    }

    /// Surfaces save / rename failures to the UI. Cleared via `clearError()`.
    /// On failure, `body` (the user's draft) is NOT rolled back.
    var pendingError: (any Error)?

    private let saver: any PageSaver
    private var saveTask: Task<Void, Never>?
    /// Debounce window between a body edit and the disk write. Rapid edits within
    /// this window coalesce into one save. Internal (not `private`) so tests can
    /// derive their poll/settle timing from the real value instead of hardcoding
    /// it — see `PageEditorViewModelTests.debounceCoalescesRapidEdits`.
    static let debounce: Duration = .milliseconds(300)

    init(page: PageMeta, body: String, saver: any PageSaver) {
        self.page = page
        self.body = body
        self.saver = saver
        self.foldedHeadings = Set(page.frontmatter.foldedHeadings ?? [])
    }

    /// Cancels any pending debounced save and schedules a new one. Called on
    /// every body mutation via `didSet`. Public so explicit "force a debounce"
    /// flows can call it directly if needed.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounce)
            } catch {
                return  // cancelled — a newer scheduleSave took over
            }
            guard !Task.isCancelled else { return }
            await self?.flushNow()
        }
    }

    /// Cancels pending debounce and saves immediately. Idempotent if nothing
    /// is pending. Used by ⌘S, window close, sidebar Page switch, and the
    /// app-lifecycle (background / terminate) flush paths.
    func flushNow() async {
        saveTask?.cancel()
        saveTask = nil

        // Drop stale fold-state keys (heading text changed or deleted
        // between saves) so `folded_headings:` doesn't accumulate dead
        // entries across rename cycles. Assigning back to foldedHeadings
        // triggers didSet which mirrors to frontmatter; scheduleSave fires
        // a 300ms-debounced redundant save (idempotent — the next pass
        // sees no orphans and is a clean no-op).
        let reconciled = MarkdownDetection.reconcileFoldedHeadings(foldedHeadings, in: body)
        if reconciled != foldedHeadings {
            foldedHeadings = reconciled
        }

        do {
            try await saver.save(page: page, body: body)
            pendingError = nil
        } catch {
            // Draft preserved in `body`; user can edit and retry, or hit the
            // alert's Retry path (reschedules a save).
            pendingError = error
        }
    }

    /// Fire-and-forget save for ⌘S keyboard binding. Wraps `flushNow` in a
    /// Task so the View doesn't await.
    func explicitSave() {
        Task { await self.flushNow() }
    }

    /// Window close / Page switch / app termination flush. Awaits the save
    /// synchronously at the call site.
    func close() async {
        await flushNow()
    }

    /// Clears `pendingError`. Called when the alert dismisses; lets the
    /// failure surface re-fire if a later save also fails.
    func clearError() {
        pendingError = nil
    }
}

/// Indirection layer between PageEditorViewModel and ContentManager. Lets tests
/// inject a stub without spinning up a real ContentManager + on-disk Nexus,
/// and lets the production wiring decide Collection-scoped vs. vault-root save
/// at construction time rather than per-call.
@MainActor
protocol PageSaver: AnyObject, Sendable {
    func save(page: PageMeta, body: String) async throws
}

/// Production PageSaver — routes to the appropriate PageContentManager variant
/// based on whether the Page lives inside a Collection or directly in the
/// Vault root.
@MainActor
final class ContentManagerPageSaver: PageSaver {
    private let contentManager: PageContentManager
    private let vault: PageType
    private let collection: PageCollection?

    init(contentManager: PageContentManager, vault: PageType, collection: PageCollection?) {
        self.contentManager = contentManager
        self.vault = vault
        self.collection = collection
    }

    func save(page: PageMeta, body: String) async throws {
        if let collection {
            try await contentManager.updatePage(page, body: body, in: collection, vault: vault)
        } else {
            try await contentManager.updatePage(page, body: body, inVaultRoot: vault)
        }
    }
}
