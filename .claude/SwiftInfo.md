### Pommora — SwiftUI Reference

Reference document for the SwiftUI implementation path. Captures research findings and architectural patterns so a future port (or a stack pivot) can move directly to implementation without re-researching the landscape.

**Status:** SwiftUI is one of two viable stack paths (React+Electron is the other). Stack decision is open. Nothing here is committed; this document captures *findings*, *patterns*, and *library options* — not Pommora's final SwiftUI architecture.

---

#### What's been verified

- **`TextEditor(text: Binding<AttributedString>)` is real and shipping** in Xcode 16.4+ (iOS 26 / macOS 26 Tahoe). Supports character-level styling (font, color, underline, kerning, links). Constraint via `AttributedTextFormattingDefinition`.
- **`apple/swift-markdown`** parses Markdown into a typed AST. Suitable as a parse / query layer.
- **Native `.draggable` + `.dropDestination` + `Transferable`** are the modern, type-safe Apple-recommended drag/drop primitives for new code.
- **Wikilinks-as-styled-spans is the easy part** — pattern-detect `[[...]]` in `AttributedString`, stamp custom attributes, attach a `pommora://page/<id>` link for tap. Matches the WWDC25 Session 280 pattern exactly.
- **SwiftUI Editor Custom** - Create a simplistic custom rich text editor in SwiftUI; headings 1-6, toggles, tables, callouts, dividers...
- **`AttributedString` round-trip is one-way out of the box.** `AttributedString(markdown:)` parses; there's no `.markdown` accessor going back. Custom attributes (e.g., wikilink IDs) work via `AttributeScope` + `CodableAttributedStringKey` + `MarkdownDecodableAttributedStringKey`, which makes them encode/decode-stable. The markdown init normalizes whitespace, drops unknown directives, and flattens table/list nuances — so the canonical save path needs a hand-rolled writer that walks Pommora's domain model (not the swift-markdown AST) back to bytes.

#### Where SwiftUI breaks for Pommora

##### Editor: TextEditor is linear (handled with segment splits)

`TextEditor` is fundamentally a single-column linear text run. It does not support inline non-text views, embedded SwiftUI views inside the prose, or block-level layout (side-by-side columns within the text flow). Pommora's `:::columns` and `:::callout` blocks require escaping the linear flow at segment boundaries.

**Two-phase plan (locked by Nathan, if SwiftUI path is picked):**

**Phase A — basic native editor with quick fork (v1 scope):**

- Native `TextEditor<AttributedString>` as the prose surface
- Heading detection and formatting (H1–H3 standard); fork quickly to add **H4–H6** and **toggles** (collapsible content blocks)
- Bold / italic / underline / inline code via `AttributedString` attributes + toolbar + standard keyboard shortcuts
- Wikilinks: pattern-detect `[[...]]`, custom attributes, styled colored text, tap-to-navigate (WWDC25 Session 280 pattern)
- Callouts and columns: segment splits (callout = styled container wrapping a sub-`TextEditor`; columns = `HStack` of sub-`TextEditor`s, equidistant)
- Horizontal divider shortcut via (---) that creates an in-page divider
- Slash menu: position-anchored popover; inserts directives/blocks at cursor
- Free from the system: undo/redo, copy/paste, spell check, autocorrect, dictation, accessibility, native cursor behavior

Phase A ships in v1 — sufficient for usable editing.

**Phase B — full custom editor (committed post-v1 core feature):**

A committed core feature for the Swift path — not optional, not Prospects, but scheduled after the app's v1 core features solidify.

- Hover-on-selection bubble toolbar (Medium / Notion-style — select text, popover with formatting actions appears)
- Richer block manipulation, drag handles, inline action affordances. Still not a full block editor; that's not the point.
- Still built on native text engine primitives where possible; falls back to NSTextView/TextKit 2 only where SwiftUI's `TextEditor` genuinely can't deliver

**NOT taken: NSTextView + TextKit 2 ground-up rebuild.** Significant AppKit work; only justified if Phase A/B hits a hard ceiling.

##### Editor: load-bearing risk on the segment-based render

The segment-based plan (page = `[Segment]`; prose segments use `TextEditor`; column/callout segments use specialized container views) **has no shipped reference implementation in any Mac app reviewed.** Bear, iA Writer, and Craft all use single-text-view-with-decorations precisely to avoid the cross-segment cursor problem: with one `TextEditor` per segment, selection cannot span segments. `@FocusState` swaps focus between editors, the previous editor commits its state, and any "select across two segments" UX has to be reconstructed in Pommora's own model. This isn't theoretical — it's the reason every shipped Mac markdown editor uses the single-view architecture instead.

Mitigations if the SwiftUI path is picked:
- Treat the cursor-flow constraint as a feature, not a bug — selections inside a callout / column don't extend out by design (matches Notion's per-block selection model).
- If cross-segment selection becomes a hard requirement, drop down to STTextView (TextKit 2) for the page surface and re-architect as decorations-on-a-single-buffer (closer to the Bear / Obsidian Live Preview pattern).

##### swift-markdown gotchas

- **Block directives use DocC `@Name(args){...}` syntax** — Apple's swift-markdown does NOT parse Pandoc / Obsidian / Docusaurus `:::name` fenced divs. If Pommora's markdown uses `:::columns` and `:::callout`, the SwiftUI path needs either a `:::` ↔ `@` preprocessor or a fork of swift-markdown.
- **`MarkupFormatter` is NOT safe as a save-path serializer.** It reformats the AST as a fresh document — whitespace, list markers, fence choice all normalized. Custom blocks can crash it. Use swift-markdown only as a parse / query / AST layer, never to write files back.
- **The implication: hand-rolled markdown writer is unavoidable.** Apple's ecosystem implicitly avoids markdown round-trip — Notes / Bear use proprietary stores. A "files canonical" Mac app is doing something Apple doesn't ship infrastructure for. The writer walks Pommora's domain model directly (not the swift-markdown AST) and emits bytes deterministically. Not technically hard; just unowned territory.

##### Spaces is feasible — and easier than the editor

The shape of Pommora's Spaces problem (one nestable `columns` container + 1D vertical flow elsewhere) is the easiest version of the structured-block-tree problem. Pure SwiftUI handles it with composable libraries.

**Recommended pattern (if SwiftUI is picked):**

- `Codable` `Block` enum as the model — serializes straight to `.space.json`
- `ReorderableVStack` from [visfitness/reorderable](https://github.com/visfitness/reorderable) for the vertical block stack
- `HSplit` from [stevengharris/SplitView](https://github.com/stevengharris/SplitView) for the columns block

**Rough edges that will cost time on this path:**
- Drop-indicator UX (no native insertion line — render from drag-session state)
- Auto-scroll while dragging (`reorderable` provides `.autoScrollOnEdges()`)
- Slash menu (caret-anchored positioning may need NSTextView)
- HSplitView polish in nested splits
- Heterogenous `Transferable` conformance per block kind

##### Custom Layout protocol — answers a different question

`Layout` (iOS 16+ / macOS 13+) controls *how children get positioned*, not *how users reorder them*. Useful only if `:::columns` ever needs custom flow behavior beyond `HStack`. For v1's equidistant columns, `HStack` suffices.

##### NavigationSplitView — top-level only

Confirmed top-level only, fixed master/detail. The right tool for the three-pane app shell (sidebar / main / inspector). Wrong tool for in-document column blocks.

---

#### Data, state, file watching

**State.** `@Observable` macro (Swift 5.9+, mature in 6.2) is the standard for new SwiftUI code — per-property tracking eliminates wasteful redraws; `@State` replaces `@StateObject`. Heavy services (VaultIndex, parsers) stay in DI, not view state, to avoid re-init on view rebuild.

**Persistence.** `GRDB.swift v7.5+` is the only credible choice for Pommora's "SQLite as index, files canonical" shape. `ValueObservation.tracking { db in ... }` is exactly the reactive primitive needed; `.values(in:)` returns an `AsyncThrowingStream` that integrates with structured concurrency. FTS5 first-class via `FTS5Pattern`. Requires Swift 6.1+/Xcode 16.3+.

SwiftData is **not** a viable alternative — it wraps Core Data, can't use a custom SQLite schema or FTS5 directly, and developers continue to bail on it through 2026 for production use cases that don't match Apple's reference patterns.

**Core code pattern.** Pure Swift Package for the data + parsing layer; the practical recommendation is to keep SwiftUI imports out of this layer so the same code is callable from a CLI tool target if needed. `actor VaultIndex` for the database boundary; mark records `Sendable`; expose `AsyncSequence` (preferred over Combine in Swift 6 strict concurrency). GRDB's `.values(in:)` *is* the reactive surface from data to UI — no wrapper needed. (This isn't an enforced rule per Pommora's architecture — see `// Features//Architecture.md` — just a discipline that keeps Swift code simpler.)

**File watching.** `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool for vault-folder watching. Use FSEventStream via a Swift wrapper (`EonilFSEvents`, or hand-rolled `FSEventStreamCreate`). Same APFS / atomic-rename gotchas as the React side: editor save = `.tmp` write + rename emits create+delete events; debounce 50–100ms by path; track outbound mtimes to ignore your own writes.

---

#### Mac OS integration — first-party advantage

The areas where SwiftUI has materially less friction than Electron — relevant to the "Mac-first cohesion" stated value. Each of these is a multi-week native-bridge project on the Electron side (often shipping a separate Swift bundle); on the SwiftUI path each is a known framework with documented APIs.

- **QuickLook (.md preview via Finder spacebar).** Ship a `QLPreviewProvider` subclass via a QuickLook Preview Extension target; declare `QLSupportedContentTypes` for `net.daringfireball.markdown`. Renders Pommora pages straight from Finder. **No realistic Electron path** without shipping a separate Swift bundle outside the app.
- **CoreSpotlight (vault-wide system search).** `CSSearchableItem` + `CSSearchableItemAttributeSet` indexes pages into Spotlight; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links results back into Pommora. First-party.
- **Share Extension (receive shares from Safari/Mail).** Add a Share Extension target conforming to `NSExtensionPrincipalClass`. Standard macOS pattern. **Impossible in pure Electron** (Issue #31984 still open).
- **NSServices ("New Pommora Page from Selection").** Declare in `Info.plist`, implement selector. One-method handler. (Electron Issue #8394 still open.)
- **MenuBarExtra (macOS 13+).** First-party menu-bar item; `.menuBarExtraStyle(.window)` enables rich popovers; instant, native-feel.
- **Sidebar vibrancy + accent.** `NSVisualEffectView` via SwiftUI's `Material` (`.regular`, `.sidebar`, etc.); automatic accent color via `Color.accentColor`; reactive theme integration. Electron's vibrancy looks ~80% right with edge-case flicker on resize and DOM bleed-through.
- **Finder file-promise drag-out.** Native via `Transferable` + `.draggable` — drag a page from the sidebar to Finder writes the file at the drop location. Electron's file-promise story has been broken for years (community workarounds write a temp file, then call `startDrag`).
- **Accessibility (VoiceOver, Dynamic Type, keyboard nav).** First-party modifiers (`.accessibilityLabel/Hint/Value/Action`); Dynamic Type free; VoiceOver rotor support free. Electron via Chromium ARIA → AX bridge has documented gaps that surface for power users.
- **Window state restoration with Spaces.** `Scene` + `@SceneStorage` integrates with NSWindow restoration including macOS Spaces. Electron's `electron-window-state` persists size/position only.

##### Distribution

- **Sparkle 2.x** is the non-MAS auto-update standard (EdDSA-signed, sandbox-compatible, full SwiftUI support via `SPUStandardUpdaterController`).
- **TestFlight for Mac** is fully shipped — same capabilities as iOS.
- **Sandboxing for MAS:** user-picked vault folders work via security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`) persisted and resolved with `startAccessingSecurityScopedResource()` on each launch. Standard pattern; no feature blocker. (Same constraint applies to Electron's MAS build.)

---

#### When to reach for AppKit interop

- **Block reorder in a vertical stack** — pure SwiftUI is sufficient (visfitness/reorderable).
- **Resizable columns with persistent splitter** — SwiftUI's `HSplitView` works but is rough; wrap `NSSplitView` via `NSViewRepresentable` for production polish.
- **Tree-shaped reorderable structure with cross-level drag** — pure SwiftUI is doable (DisclosureGroup + manual NSItemProvider) but not pretty. Reference: [shufflingB/swiftui-macos-tree-list-demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo).
- **Unified cursor flow across columns / callouts** — only achievable via NSTextView/TextKit 2 (STTextView).

---

#### Interactful — clarification

**Interactful is NOT a library.** It is a closed-source App Store reference app by Harley Thomas (current v6.0.5, April 2026) that displays interactive demos of stock SwiftUI components alongside copy-pasteable source code. It is useful as a desk-side learning tool while building, but contributes zero runtime code to a Pommora SwiftUI build — there is no SPM endpoint, no GitHub repo, no `import Interactful`.

If Pommora ever pivots to SwiftUI, the actually-useful component libraries to know about are listed in `Resources.md` under the SwiftUI section: `stevengharris/SplitView`, `visfitness/reorderable`, `SwiftUIX/SwiftUIX`, plus Apple's first-party additions (WWDC25's new `dragContainer` modifier, multi-item `.draggable`, `DragConfiguration`, `onDragSessionUpdated`).

---

#### Editor evaluation context (for the React side, mirrored here for completeness)

The React-path editor evaluation that resolved on BlockNote (open-source MPL-2.0 core) doesn't directly apply to SwiftUI — the SwiftUI editor primitive is `TextEditor` + `AttributedString`, which is a different paradigm entirely (system text engine vs. third-party block editor library). If SwiftUI is picked, the editor work is "build the hybrid segment renderer" rather than "configure a third-party library."

---

#### Maintenance notes

- This file captures research findings, not committed architecture. The "recommended pattern" notes are best-known approaches as of the audit, not Pommora's locked design.
- Update as new SwiftUI research lands (WWDC sessions, Apple sample code, library updates).
- If the React+Electron path is locked permanently, this file can be archived. If SwiftUI is picked, the contents promote to the active Architecture and Domain-Model docs.
