### Pommora — SwiftUI Reference

Reference document for the SwiftUI implementation path. Captures research findings and architectural patterns so a future port (or a stack pivot) can move directly to implementation without re-researching the landscape.

**Status:** SwiftUI is one of two viable stack paths (React+Electron is the other). Stack decision is open. Nothing here is committed; this document captures *findings*, *patterns*, and *library options* — not Pommora's final SwiftUI architecture.

---

#### What's been verified

- **`TextEditor(text: Binding<AttributedString>)` is real and shipping** in Xcode 16.4+ (iOS 26 / macOS 26 Tahoe). Supports character-level styling (font, color, underline, kerning, links). Constraint via `AttributedTextFormattingDefinition`.
- **`apple/swift-markdown`** parses Markdown into a typed AST. Suitable as a parse / query layer.
- **Native `.draggable` + `.dropDestination` + `Transferable`** are the modern, type-safe Apple-recommended drag/drop primitives for new code.
- **Wikilinks-as-styled-spans is the easy part** — pattern-detect `[[...]]` in `AttributedString`, stamp custom attributes, attach a `pommora://page/<id>` link for tap. Matches the WWDC25 Session 280 pattern exactly.
- **`AttributedString` round-trip is one-way out of the box.** `AttributedString(markdown:)` parses; there's no `.markdown` accessor going back. Custom attributes (e.g., wikilink IDs) work via `AttributeScope` + `CodableAttributedStringKey` + `MarkdownDecodableAttributedStringKey`, which makes them encode/decode-stable. The markdown init normalizes whitespace, drops unknown directives, and flattens table/list nuances — so the canonical save path needs a hand-rolled writer that walks Pommora's domain model (not the swift-markdown AST) back to bytes.

#### Where SwiftUI lands for Pommora

##### Editor: two options

The SwiftUI Pommora editor has **two options**:

- **Option 1 — Native Swift markdown editor.** Two sub-approaches with the same UX outcome: fork **Clearly** ([Shpigford/clearly](https://github.com/Shpigford/clearly) — native AppKit/SwiftUI markdown editor with a working `MarkdownSyntaxHighlighter` in its `ClearlyCore` Swift Package, fold-state plumbing, and a polished editor shell; license FSL-1.1-MIT, converts to MIT Feb 2028), or build an original native editor on `NSTextView` / AppKit text-engine primitives. Either delivers source-with-decorations on a native text engine — the document IS the markdown string, styling layered as text attributes, Obsidian-style Live Preview (markers hidden when cursor leaves a construct, revealed when it enters) implemented via attribute manipulation on selection change. Full native text behavior (smart quotes, system dictionary, AppKit caret and selection). GFM table inline rendering requires custom layout fragments; TextKit 2 has confirmed production instability for advanced layout work — factor into build planning.

- **Option 2 — WKWebView hosting a JS markdown editor. (Likely direction if SwiftUI is chosen.)** Host **Tiptap**, **Milkdown**, or **BlockNote** in a WKWebView. All three have solid markdown translation — they read from and write to on-disk Markdown cleanly, keeping files canonical. The JS editor handles the editor surface; the SwiftUI shell wraps it with a native toolbar, menus, keyboard shortcuts, three-pane layout, sidebar, and inspector — everything outside the editor canvas stays native. The editor canvas is styled to match the design system (SF Pro via `font-family: -apple-system`, Pommora's design tokens as CSS custom properties). Scroll physics and caret animation are WebKit's rather than AppKit's — the main UX seam. WWDC25 shipped a first-class `WebView` in SwiftUI (iOS 26.0+ / macOS 26.0+), eliminating the `NSViewRepresentable` wrapper for those targets; older OS targets keep using `WKWebView` via `NSViewRepresentable`. MarkEdit (App Store) is the production reference for this architecture.

  Implementation shape: the editor's JS bundle (CodeMirror 6 / Tiptap / Milkdown / BlockNote) ships **inside** the Pommora `.app` — fully self-contained, no external network fetches at runtime. Served to the WebView via a custom URL scheme handler (`WKURLSchemeHandler` registered for e.g. `editor://`), because WKWebView treats `file://` URLs as a null origin and blocks `<script type="module">` execution (WebKit bug #154916). The custom-scheme workaround is the Apple-documented pattern. Because the editor doesn't fetch from external origins, the known caveat that custom schemes are treated as insecure for cross-origin fetch doesn't apply. `WKScriptMessageHandler` carries editor events into Swift; Swift writes Markdown to disk and updates SQLite. Only Markdown crosses the bridge on save. iOS/iPad parity is intact — WKWebView is cross-Apple-platform.

  Editor candidates — pick at SwiftUI commit time. Needs to be evaluated in practice before committing:
  - **Tiptap (MIT)** — headless ProseMirror framework; most configurable; every package Pommora needs ships MIT.
  - **Milkdown (MIT)** — markdown-first by design; round-trip integrity built into the framework; plugin ecosystem covers slash menu, history, clipboard, math, upload.
  - **BlockNote (MPL-2.0)** — batteries-included; built on Tiptap; fastest to a working editor. Avoid `@blocknote/xl-multi-column` (GPL-3.0 or commercial) — build the columns block in core instead.
  - **MarkdownEditor ([Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor), MIT)** — a pre-packaged Swift Package wrapping CodeMirror 6 in WKWebView with a clean SwiftUI API (`EditorWebView(text: $markdown)`). Ships with Obsidian-style syntax hiding built in (`hideSyntax: true` default), GFM tables via the `GFM` lezer extension, SF fonts as default, light/dark theme, and a command palette triggered by `/`. Missing for Pommora: `:::callout`, `:::columns`, and wikilinks (all addable as CM6 extensions in TypeScript). Personal project, one contributor, v1.0.1 — recommend forking rather than depending. CM6 is the engine under the hood; this package provides the UI on top. Requires seeing it in practice before committing.

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

The React-path editor evaluation resolved on two co-primary candidates — BlockNote (MPL-2.0) and Tiptap (MIT), both ProseMirror-React block editors and a different paradigm from anything on the SwiftUI side. If SwiftUI is picked, the editor work is either forking a working native editor (Clearly) or building an original on native text-engine primitives — not configuring a third-party JS library.

---

#### Maintenance notes

- This file captures research findings, not committed architecture. The "recommended pattern" notes are best-known approaches as of the audit, not Pommora's locked design.
- Update as new SwiftUI research lands (WWDC sessions, Apple sample code, library updates).
- If the React+Electron path is locked permanently, this file can be archived. If SwiftUI is picked, the contents promote to the active Architecture and Domain-Model docs.
