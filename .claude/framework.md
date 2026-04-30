# Framework — Pommora

The single source for **what we're building, where we are, and what's locked**. Read before planning any feature, scoping work, or making architectural decisions. The code answers *how*; this file answers *what* and *why*.

---

## Vision

A native macOS markdown and plaintext editor built against the macOS 26 design language. Folder-based (virtual folders containing references to files anywhere on disk), aesthetically aligned with current Apple Design Resources, fully native SwiftUI.

Full product spec: `PRD/` at the repo root.

---

## Current state

Walking skeleton. Stable base: commit `0ab792f` ("Rewrite CLAUDE.md…"). What's shipped:

- Three-column `NavigationSplitView` (sidebar / folder content / editor) with `.prominentDetail` style — sidebar and middle column resize independently; the editor absorbs all width changes.
- Sidebar with four sections (`Favorites`, `Folders`, `Files`, `Tags`) plus a `Recents` row at the top. `Favorites` and `Tags` are header-only placeholders.
- `Folders` lists `VirtualFolder`s as flat rows (no inline file children).
- `Files` lists orphan `FileReference`s (`folder == nil`) directly in the sidebar `List` — no inner scroll cap, the sidebar's own `List` scrolls.
- Section order is user-rearrangeable and persists in `@AppStorage("sidebarSectionOrder")`.
- File reading + basic editing via `TextEditor`.
- Recents — files-only, cap 50, bucketed `Today` / `Yesterday` / `Previous 7 Days` / `Older`. Display order is **snapshotted on appear** so tapping a file doesn't jump it to the top mid-interaction.
- Search — `.searchable(placement: .sidebar)`. Filenames first, headings second; matched-range highlight via `inlinePresentationIntent = .stronglyEmphasized`. Heading parsing is lazy and session-cached in `LibrarySearchCache`.
- Drag-and-drop — string-prefixed payloads (`"folder:UUID"` / `"file:UUID"`). Live reorder via `isTargeted:` callback wrapped in `withAnimation(.snappy)`. Cross-context moves: drop a file onto a folder row → moves into folder; drop onto the `Files` header or any orphan row → becomes orphan.
- Sidebar add/move — empty-space context menu: `New Folder` + `Add Files…`. Folder right-click: `Add Files to [Folder]…`. New folders insert at order 0 (existing shift +1) with numeric disambiguation on name collision.

---

## v1.0 scope

Ship a working skeleton. Nothing beyond this list.

- Three-column `NavigationSplitView`.
- Virtual folders + orphan files.
- File reading and basic editing via `TextEditor`.
- Recents (cap 50, bucketed by date).
- Search (filenames + headings).
- Drag-and-drop reorder within sidebar.

**Hard constraints for v1.0:**

- No AppKit wraps — `NSViewRepresentable` is off the table ("swift ONLY items").
- No auto-save.
- No cloud sync, no accounts.
- No rendering toggle.
- macOS 26 only — no backward compat.

---

## v1.1 planned iterations

| Iteration | What |
|---|---|
| A | Security-scoped bookmarks (`bookmarkData: Data` on `FileReference`, additive — no destructive migration), inline "Locate…" UX for missing files |
| B | `NSViewRepresentable`-wrapped `NSTextView` for the editor pane |
| C | Rendering toggle (binary: Raw / Styled) |
| D | Outline panel |

---

## Standing constraints

These are non-obvious facts that don't surface from reading the code or git history.

- **No AppKit in v1.0.** Nathan explicitly: "swift ONLY items." `NSViewRepresentable` is deferred to v1.1.
- **Auto-save is OFF.** No save mechanism in MVP. `FileIO.write` exists but is not wired to any save trigger. This is intentional and continues through v1.1.
- **DebugSeed runs in DEBUG builds on app appear.** It seeds folders + files. When testing with large orphan counts, use `DebugSeed` rather than manually adding files.
- **`PBXFileSystemSynchronizedRootGroup`.** New `.swift` files in `Pommora/Pommora/` compile automatically — no `project.pbxproj` edit needed.
- **DerivedData hash to pin.** `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Always pin with `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx` when running `xcodebuild`. See L-005 in `lessons.md`.
- **Theme setting** — Settings scene exposes Light / Dark / Device picker (default = Device). App-only override via `.preferredColorScheme(...)`. Stored on `AppState.themePreference`. *Not yet implemented in code.*

---

## Deferred / locked decisions

Decisions that constrain future work.

1. **MVP cut = walking skeleton.** v1.0 ships without rendering toggle, file watching, or security-scoped bookmarks. Those are v1.1.
2. **Drag reorder in `.listStyle(.sidebar)`** — architecturally blocked by `NSOutlineView` (legacy blue insertion bar). The macOS 26 container-drag API requires `.listStyle(.inset)` or `.listStyle(.plain)`. Deferred to v1.1. See L-006 in `lessons.md`.
3. **Rendering toggle is binary** when it returns: Raw (mono, plain) / Styled (SF + formatted markdown). The 3-mode design from 2026-04-26 is dropped.
4. **Missing files** — auto-removed silently on launch in MVP. v1.1 (with bookmarks) shifts to inline "Locate…" UX.
5. **Outline panel** — not in MVP. v1.1 Iteration D.
6. **Future view modes** (icon, list, gallery) — deferred. Column view only.
7. **`bookmarkData: Data` on `FileReference`** — additive in v1.1 Iteration A. No destructive migration.
8. **No AppKit wraps in v1.0.** `NSViewRepresentable` off the table until v1.1.

---

## Planning checklist

Run before scoping any task.

- [ ] Does this touch drag/drop? The sidebar drag architecture is locked — see deferred decision #2.
- [ ] Does this require AppKit? Out of scope for v1.0. Surface to Nathan.
- [ ] Does this add or change a `NavigationSplitView`? Must use `.prominentDetail`. (L-003)
- [ ] Does this add a new file code path? Must handle both folder-resident and orphan files identically. (L-004)
- [ ] Does this touch a SwiftUI modifier? Verify against the `.swiftinterface` first — and follow `swift-uix-rules.md`. (L-002)
