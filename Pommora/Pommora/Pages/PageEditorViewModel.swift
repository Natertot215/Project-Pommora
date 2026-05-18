import Foundation
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
    /// the frontmatter that gets preserved on every save.
    let page: PageMeta

    /// Editable body. Every keystroke updates this; `didSet` schedules a
    /// debounced save 300ms from now. Multiple rapid edits coalesce.
    var body: String {
        didSet { scheduleSave() }
    }

    /// Surfaces save failures to the UI. Cleared on the next successful save.
    /// On failure, `body` (the user's draft) is NOT rolled back.
    private(set) var pendingError: (any Error)?

    private let saver: any PageSaver
    private var saveTask: Task<Void, Never>?
    private static let debounce: Duration = .milliseconds(300)

    init(page: PageMeta, body: String, saver: any PageSaver) {
        self.page = page
        self.body = body
        self.saver = saver
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

/// Production PageSaver — routes to the appropriate ContentManager variant
/// based on whether the Page lives inside a Collection or directly in the
/// Vault root.
@MainActor
final class ContentManagerPageSaver: PageSaver {
    private let contentManager: ContentManager
    private let vault: Vault
    private let collection: Pommora.Collection?

    init(contentManager: ContentManager, vault: Vault, collection: Pommora.Collection?) {
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
