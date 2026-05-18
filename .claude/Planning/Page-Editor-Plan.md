### Page Editor — Research + Plan (v0.2.7 / v0.2.8 patches)

Implementation plan for the Pages editor surface. Locks the **WKWebView + MarkEdit-pattern native shell + 7-message JSON bridge** architecture as stack-agnostic. **Editor library is still under decision** — Tiptap (ProseMirror, vanilla TS, MIT) is the leading candidate but NOT solidified. Pages + Tabs ship as v0.2.x patches (v0.2.7 + v0.2.8 in either order); both must be done before v0.3.0 (Properties) begins.

This document supersedes the Option 1 vs Option 2 framing in `// Features//Pages.md`'s "Editor surface" section. After this lands, Pages.md gets the summary; this doc is the deep spec. The library-specific sections below (Tiptap node specifics, bundle config) all assume Tiptap; if the editor pick changes at v0.2.7 prep, expect a 1-2 day swap for sibling ProseMirror editors (Milkdown, BlockNote) or 3-5 days + Pages.md spec rewrite for a paradigm switch (CodeMirror 6).

> **Editor library decision history:**
> - **2026-05-17 (early session):** initial recommendation was CodeMirror 6 (source-with-decorations / Obsidian Live Preview pattern). Reversed to Tiptap at Nathan's direction — WYSIWYG editing is the preferred interaction; Live Preview explicitly out of scope.
> - **2026-05-17 (end-of-session correction):** Tiptap demoted from "locked" to "leading candidate." Final pick reopens at v0.2.7 implementation start. See "What we give up by choosing Tiptap" + "Hot-swap disciplines" sections below for the candidate trade-offs.

> **Roadmap reorder (2026-05-17 end-of-session):** Pages + Tabs were originally framed as v0.3.0 + v0.4.0 minor versions. Restructured to ship as v0.2.x patches: v0.2.7 = Pages editor (prose + standard Markdown), v0.2.8 = Tabs (multi-instance + persistence). Order between v0.2.7 and v0.2.8 is interchangeable. v0.2.9 + v0.2.10 = Pages-editor additions (directives + heading fold + slash menu; wikilinks + rename cascade). v0.3.0 becomes Properties.

---

#### Context

The v0.2 paradigm-scaffolding branch has shipped real CRUD for Pages (create / rename / delete in `Pommora/Pommora/Content/ContentManager.swift`), but clicking a Page in the sidebar is a no-op — there's no editor. v0.3 lands the editor.

The spec at `// Features//Pages.md` calls for:

- **WYSIWYG editing** — typing `**bold**` immediately becomes **bold** (no asterisks visible); `# H1 ` becomes a heading on space; etc. Markdown is the input shorthand, not the rendered output.
- **Markdown shortcuts** (Notion / Bear pattern) for fast formatting without leaving the keyboard
- **Wikilink autocomplete** — popover triggered by `[[`
- **Wikilinks** — rendered as **styled colored inline text** (visually identical to Obsidian-style hyperlinks, even though technically inline nodes in Tiptap's model); no chip background, no icon prefix
- **Heading fold** — chevron next to heading collapses the visible region
- **Two Pommora directives** — `@Columns` (multi-column) and `:::callout` (outlined box)
- **Standard Markdown** — paragraphs, headings (H1–H5), lists, code, GFM tables, blockquotes (filled box + left bar), hr
- **Quiet chrome** — floating toolbar on text selection (Tiptap's "bubble menu" pattern); slash menu (`/`) for inserting directives; no always-visible block UI

The editor renders prose, not source. Markdown only round-trips at the file boundary.

---

#### Leading direction: Tiptap (ProseMirror) in WKWebView, MarkEdit-pattern native shell — NOT LOCKED

> **Reopen this decision at v0.2.7 implementation start.** As of end-of-2026-05-17 the editor library is the leading candidate, not solidified. The architecture (WKWebView + 7-message bridge + `WKURLSchemeHandler`) is stack-agnostic and survives any editor pick. The text below assumes Tiptap; sections like "Why Tiptap over BlockNote / Milkdown" still apply as evaluation material.

**Tiptap** (`@tiptap/core` + `@tiptap/markdown` + selected extensions, all MIT) is the editor engine. It runs inside a `WKWebView` driven by SwiftUI's `WebView` primitive (macOS 26+). The Swift app shell stays native; the editor canvas is a single-purpose JS bundle shipped inside `.app/Contents/Resources`.

The shell architecture is the same **MarkEdit pattern** evaluated earlier — a native Swift+AppKit container, a `WKURLSchemeHandler` for loading ESM bundles, a narrow JSON message bridge for save/theme/wikilink-query. MarkEdit's choice of CodeMirror inside that shell isn't load-bearing; the shell is the reusable part.

##### Why Tiptap over BlockNote / Milkdown

| Capability | Tiptap | BlockNote | Milkdown |
|---|---|---|---|
| WYSIWYG editing | ✅ default | ✅ default | ✅ default |
| Markdown round-trip via first-party extension | ✅ `@tiptap/markdown` (MIT) with `parseMarkdown`/`renderMarkdown` per node | ⚠️ `blocksToMarkdownLossy` / `tryParseMarkdownToBlocks` (lossy at boundary) | ✅ remark-based, near-perfect |
| Quiet "prose-flow" chrome (no block UI by default) | ✅ headless; you choose which chrome to wire | ❌ blocks-first by design; drag handles + `+` markers on every paragraph | ✅ vanilla; Crepe preset adds block UI |
| `:::callout` / `:::columns` directives | ✅ custom `Node.create` + `markdownTokenizer` (admonition tutorial is a 1:1 fit) | ⚠️ custom block spec; multi-column requires GPL or commercial `xl-multi-column` | ✅ `containerDirective` via remark-directive |
| Wikilinks as styled inline text (visually not chips) | ✅ inline node + CSS — looks like styled text, technically a node | ⚠️ inline node only via custom spec | ✅ inline node + CSS |
| Heading fold (chevron-collapse) | ⚠️ custom decoration plugin (~50 LOC) | ❌ N/A | ⚠️ custom decoration plugin |
| Bundle size (no React framework) | ~250 KB minified+gzipped | ~1 MB+ (React required) | ~400 KB |
| License (full editor + extensions Pommora needs) | All MIT, all in `@tiptap/*` (the paid `@tiptap-pro/*` scope is unrelated — Cloud / AI / Collaboration services) | Core MPL-2.0; multi-column GPL-3.0 or commercial Business subscription | All MIT |
| Production reference | Notion-likes, GitHub web editor, every editor BlockNote is built on top of | Jupyter notebooks, blocks-first SaaS | Typora-likes, markdown-canonical apps |
| Framework dependency | None — vanilla TS works | React (heavy DOM) | Vue or vanilla |

**Why not BlockNote:** the multi-column package is the one BlockNote dependency that's GPL-or-commercial, and we'd need it for `@Columns`. Plus BlockNote's block-on-every-paragraph chrome is the opposite of Pommora's quiet-prose aesthetic.

**Why not Milkdown:** genuinely the closest competitor to Tiptap for Pommora. Markdown-first round-trip is its strongest feature; the `containerDirective` support for `:::callout` is first-class. The choice tips to Tiptap because (1) Tiptap's documentation is more extensive (3,500+ snippets vs Milkdown's ~170), (2) the visual demo at [tiptap.dev](https://tiptap.dev/) matches Pommora's intended chrome almost exactly out of the box, (3) Tiptap has explicit support for vanilla / no-framework bundles, keeping the WKWebView bundle small.

---

#### What we give up by choosing Tiptap over CodeMirror

Documenting these explicitly so they don't surprise us later:

1. **No Live Preview / no source-with-decorations.** You never see `**` or `[[` syntax markers in the editor — they're consumed by input rules at the moment of typing. The raw Markdown source is only visible if you open the file in an external editor (`vim`, `cat`, etc.).
2. **Markdown round-trip is near-perfect, not byte-perfect.** Tiptap's working state is a ProseMirror JSON document; saving runs `editor.storage.markdown.getMarkdown()`. Custom node serializers cover the two Pommora directives. Edge cases: normalized whitespace, list marker style consistency, table column padding. None of these affect the rendered output or any agent's ability to read the file — they're cosmetic to the bytes.
3. **You can't put your cursor "inside" wikilink syntax.** The `[[ ]]` brackets don't exist in the WYSIWYG view. Editing a wikilink means clicking it → popover with the target picker. (Power-user feature: a "View Source" toggle could show the raw Markdown for any selection — deferred Prospect.)
4. **Auto-pair behavior changes meaning.** In a source editor, typing `**` produces `**|**` and you see the markers. In Tiptap, typing `**word**` is an input rule that toggles bold instantly — no markers ever shown. Same end result, different model.

All four are acceptable per Nathan's direction. The first three become Prospects if a future user really wants source-leaning mode.

---

#### Hot-swap disciplines — protecting future editor flexibility

The architecture below is deliberately structured so that swapping editors (Tiptap → Milkdown / BlockNote / CodeMirror) is **1-5 days of JS-side work, zero Swift changes**. This holds only if these six disciplines are followed during implementation and forever after:

1. **The 7-message bridge contract is the firewall.** Don't expand it. Adding messages is a smell — it usually means editor-specific state is leaking across the boundary. If a feature wants the editor to expose its internal model to Swift, find a different way.
2. **Frontmatter never crosses the bridge.** The editor sees the body markdown string only. Frontmatter (id, tier1/2/3, properties) stays Swift-side; the v0.5 property panel UI lives in SwiftUI and edits `PageFrontmatter` through `ContentManager`. The WebView never sees it.
3. **Editor JSON state never persists to disk.** Markdown on disk is canonical. The editor's working state (ProseMirror JSON for Tiptap, EditorState for CodeMirror, etc.) is throwaway. Trade-off: undo dies on tab close — acceptable, matches Bear / MarkEdit / Obsidian source mode.
4. **Theme via CSS custom properties.** CSS variables (`--pommora-accent`, `--pommora-code-bg`, etc.) don't care which editor uses them. Same theme bridge works in Tiptap, BlockNote, CodeMirror, or any future replacement.
5. **Tests stub the bridge, not the editor.** `PageEditorViewModel` tests use a `BridgeProtocol` stub (see "Test approach" below) — never instantiate Tiptap in tests. Editor swaps don't break unit tests.
6. **Bundle build pipeline lives in `EditorSource/`.** Self-contained TypeScript project with its own package.json + esbuild config. Swap target = swap the whole folder, not surgical changes inside it. Swift side never imports anything from `EditorSource/`.

Swap effort estimates if Tiptap turns out wrong:

| Swap target | Same paradigm? | Same engine family? | Estimate |
|---|---|---|---|
| **Tiptap → Milkdown** | ✅ WYSIWYG | ✅ ProseMirror | **1-2 days** (sibling editor; Crepe preset speeds it up) |
| **Tiptap → BlockNote** | ✅ WYSIWYG | ✅ ProseMirror | **1-2 days** (adds React ~150 KB; multi-column requires custom build) |
| **Tiptap → CodeMirror 6** | ❌ paradigm switch | ❌ different engine | **3-5 days + Pages.md spec rewrite** (Live Preview replaces WYSIWYG) |

These estimates assume the disciplines above are followed. Violate them and swap cost balloons unpredictably.

---

#### Apple-native styling — what "Apple-like" means in the WKWebView canvas

Outside the editor canvas, the rest of Pommora is pure SwiftUI semantic colors + Materials + SF Pro via the system font scale (`// Guidelines//UIX-Guide.md`). Inside the canvas, "Apple-like" means a small, deliberate set of decisions:

1. **Type stack: `font-family: -apple-system, BlinkMacSystemFont, system-ui;`** for prose; `font-family: ui-monospace, "SF Mono", Menlo, monospace;` for code blocks. CSS `-apple-system` resolves to SF Pro on macOS automatically — no font bundling, no fallback chain to worry about.
2. **Use the `-apple-system-*` text styles where possible** — `font: -apple-system-body;`, `font: -apple-system-headline;`. These pick up Apple's optical scaling and weight choices for free, and respect macOS's text-size accessibility setting.
3. **No web-default chrome.** Reset margins, restrained line-height (1.55 for prose, 1.45 for code), no rounded button borders, no `:hover` color flashes that don't exist in AppKit, no drop shadows on focused elements (use accent-tinted outline-offset instead, matching the macOS focus ring).
4. **Selection color = system accent.** `::selection { background: var(--pommora-selection); }` where `--pommora-selection` is the accent color at 25% opacity (matches `NSColor.selectedTextBackgroundColor` behavior).
5. **Caret = system caret.** Plain `1px` solid caret, no animated blink override, no thick custom rendering. WKWebView's default caret already inherits the macOS appearance.
6. **Scroll physics:** WebKit's, not AppKit's. This is the one UX seam — kinetic scroll feels slightly different in a web view. Acceptable per spec (MarkEdit accepts the same tradeoff).
7. **Quiet decorations.** Code blocks: filled background only, no border. Blockquotes: filled background + left accent bar (matching the Calendar.app event-card pattern per `Pages.md:34`). Callouts: outlined box with subtle border. Wikilinks: colored inline text only — no underline, no chip background, no icon prefix.
8. **Floating toolbar on selection.** Tiptap's "bubble menu" pattern — toolbar appears on text selection, disappears on collapse. Styled as a small floating Material-bg pill with bold/italic/code/link buttons. Matches the macOS text-selection menu instinct.
9. **Slash menu (`/`) for directive insertion.** Tiptap's suggestion plugin pattern — typing `/` at line start opens a popover with directives (Callout, Columns, Code block, Table). Styled as a translucent floating panel with SF Symbol icons.
10. **Theme tokens.** Swift owns the brand values in `Color+Pommora.swift`; at editor mount, a `themeUpdate` message bridges them to CSS custom properties (`--pommora-accent`, `--pommora-code-bg`, `--pommora-callout-border`, etc.). On `colorScheme` change, send a new `themeUpdate` — don't reload the editor.

The result: an editor canvas that reads as continuous with the surrounding SwiftUI shell. Users who notice "it feels native" but can't articulate why is the bar.

---

#### Architecture — file layout

```
Pommora/Pommora/Pages/
  PageEditorView.swift               ← SwiftUI host; constructs the VM, hosts the WebView
  PageEditorViewModel.swift          ← @MainActor @Observable; bridges PageFile ↔ editor
  PageEditorBridge.swift             ← WKScriptMessageHandler + WKURLSchemeHandler
  PageEditorMessages.swift           ← Codable message types for the JS bridge
  PageEditorTheme.swift              ← Color+Pommora.swift → ThemeTokens struct

  Editor/                            ← shipped inside .app/Contents/Resources
    index.html
    bundle.js                        ← built Tiptap bundle (esbuild, single file)
    bundle.css

  EditorSource/                      ← TypeScript source for the bundle, built by a Run Script phase
    src/
      main.ts                        ← entry — wires extensions, exposes window.pommoraEditor API
      bridge.ts                      ← postMessage + receive handlers
      theme.ts                       ← reads CSS custom properties, applies to editor
      extensions/
        callout.ts                   ← Node.create for :::callout (admonition pattern)
        columns.ts                   ← Node.create for @Columns
        wikilink.ts                  ← Node.create inline + Suggestion plugin for [[ autocomplete
        bubbleMenu.ts                ← floating toolbar on selection
        slashMenu.ts                 ← / for directive insertion
        headingFold.ts               ← chevron-toggle next to headings, hide collapsed region
        markdownConfig.ts            ← @tiptap/markdown setup + per-node serializer registration
    package.json
    esbuild.config.mjs
    tsconfig.json
```

No React, no Vue. Tiptap works as vanilla TypeScript (`@tiptap/core` + `@tiptap/pm`). Bundle size estimate: ~250 KB minified+gzipped (Tiptap core + markdown extension + our 7 custom extensions). esbuild for the bundle build.

##### Why a custom URL scheme handler

WKWebView treats `file://` as a null origin and blocks `<script type="module">` ([WebKit bug 154916](https://bugs.webkit.org/show_bug.cgi?id=154916)). The fix is registering a `WKURLSchemeHandler` for `pommora-editor://` that serves `index.html`, `bundle.js`, `bundle.css` from `Bundle.main.resourceURL/Editor/`. This is exactly what MarkEdit does. Without it, the editor either won't load ES modules at all or has to inline the entire bundle into a `<script>` tag (which wrecks devtools).

---

#### The Swift ↔ JS bridge — 7 messages

```
                          Swift                                                   JS
                          ─────                                                   ──
init             →        { markdown: String, theme: ThemeTokens }                editor mount
save             ←        { markdown: String }                                    debounced on edit (200ms)
themeUpdate      →        { theme: ThemeTokens }                                  on colorScheme / accent change

query            ←        { prefix: String }                                      typing in [[ ]] (v0.3c)
queryResults     →        { entries: [{id, title, kind, icon?}] }                 response (v0.3c)
openWikilink     ←        { id: String, kind: "page"|"context"|"item" }           click on rendered wikilink (v0.3c)

editorError      ←        { message: String, fatal: Bool }                        any uncaught error
```

Seven message types across all three editor versions. Adding more is a smell — it usually means we've leaked editor state into Swift or vice versa.

**Bridge contract:**
- JS owns the entire editor state (Tiptap's ProseMirror JSON). Swift never reads it.
- Swift owns the file on disk. JS never touches the filesystem.
- Frontmatter never crosses the bridge. The editor sees the body markdown only; the frontmatter property panel is a separate SwiftUI surface that edits `PageFrontmatter` through `ContentManager`.
- Theme tokens cross only on init + colorScheme change — not on every paint.
- All messages are Codable structs in `PageEditorMessages.swift` for type safety on the Swift side.

---

#### Save path — linear

```
[ user types in Tiptap editor ]
       │
       │ 200ms debounce inside the editor (via @tiptap/markdown onUpdate)
       ▼
[ markdown = editor.storage.markdown.getMarkdown() ]
       │
       ▼
[ JS posts { type: "save", markdown } via WKScriptMessageHandler ]
       │
       ▼
[ Swift: PageEditorViewModel.bodyDidChange(markdown) ]
       │
       │ 300ms debounce inside the VM (defense in depth)
       ▼
[ pageFile.body = markdown ]
       │
       │ ContentManager.updatePage(...) ← NEW in v0.3a
       │   - runs PageValidator (cheap, no IO)
       │   - calls PageFile.save → AtomicYAMLMarkdown.write (atomic temp+rename)
       │   - updates the in-memory PageMeta in pagesByCollection / pagesByVaultRoot
       ▼
[ <title>.md on disk, frontmatter preserved ]
```

`ContentManager.updatePage` is the one new method v0.3a needs to add — mirrors the existing `updateItem(_:in:vault:)` at [ContentManager.swift:389](Pommora/Pommora/Content/ContentManager.swift#L389). Two variants (Collection-scoped + vault-root) consistent with the rest of the file.

Load is the reverse: `PageFile.load` → `PageEditorViewModel` holds the body → init message to JS → `editor.commands.setContent(markdown, { contentType: 'markdown' })`.

The JSON working state (Tiptap's ProseMirror doc) is **never** serialized to disk. Close the tab = lose undo stack. Matches Notion, Bear, Obsidian (in source mode), MarkEdit. Stashing JSON state for tab persistence is a v1.x Prospect.

---

#### Opening behavior — detail pane (v0.3) → tabs (v0.4), new window on demand

Nathan's direction (2026-05-17): "Pages should be able to be opened in a new tab by default, or have the option to be opened in a new window."

##### v0.3 default — open in the detail pane (single Page at a time)

Until Tabs land at v0.4, clicking a Page row in the sidebar opens the Page **in the detail pane**, replacing the existing `CollectionDetailView` / `VaultDetailView` / `ContextDetailPlaceholder` for that selection. Only one Page can be open at a time in the current window — switching to a different Page closes the previous one (its body is already auto-saved by the debounce loop).

This routes through the existing `SidebarDetailView` dispatcher at [Pommora/Pommora/Detail/SidebarDetailView.swift](Pommora/Pommora/Detail/SidebarDetailView.swift) — when the sidebar selection is a `.page(PageMeta)`, it renders `PageEditorView` instead of falling through to a placeholder. No new SwiftUI navigation primitives needed in v0.3.

##### v0.4 — new tab in the current window (default after Tabs land)

Once the v0.4 tab strip ships, clicking a Page row opens it as a **new tab in the current window**. If already open, focus existing tab instead of duplicating. The tab strip lives in the navigation toolbar (per `// Features//Navigation-Bar.md`), holds an ordered array of opened tabs in window-scoped state, and routes each tab's content to the detail pane. Pages render `PageEditorView`; Contexts render their composed-blocks placeholder (until v0.9); Vaults/Collections render the existing detail views.

Tab behavior (v0.4):
- Click on Page row → if already open, focus existing tab; else append new tab and focus
- `⌘W` → close current tab; if last tab, fall back to a blank state (no editor)
- `⌘T` → blank new tab with a placeholder (post-v0.4 Quick Capture entry point)
- Drag to reorder; persist tab list to `.nexus/state.json`

##### Optional — open in a new window

User invokes from any of:
- **Right-click a Page row** → "Open in New Window"
- **`⌥⌘O` keyboard shortcut** while a Page row is selected in the sidebar (or while a Page tab is focused — opens the current tab in a new window)
- **Drag a Page row out of the sidebar** to the desktop or another part of the screen (drag-promotion-to-window; macOS-native gesture, supported by `Transferable` + custom drop handling)
- **File menu → New Page Window** (with submenu of recent / pinned Pages, post-v0.3a polish)

##### SwiftUI scene wiring

```swift
@main
struct PommoraApp: App {
    var body: some Scene {
        // Main app shell — sidebar + detail + tab strip
        WindowGroup {
            ContentView()
        }

        // Standalone Page windows — one scene type, opened by Page ID
        WindowGroup(for: PageRef.self) { $ref in
            if let ref { StandalonePageWindow(ref: ref) }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings { SettingsView() }
    }
}

// PageRef = Codable value carrying enough to find the Page after a launch.
// Stored in scene-restoration data; survives quit/relaunch.
struct PageRef: Hashable, Codable {
    let pageID: String                // PageFrontmatter.id (ULID)
    let vaultID: String
    let collectionID: String?         // nil = directly in vault root
}
```

Triggering from anywhere with the environment action:

```swift
@Environment(\.openWindow) private var openWindow

// in a context menu or shortcut handler:
openWindow(value: PageRef(pageID: page.id, vaultID: vault.id, collectionID: collection?.id))
```

`StandalonePageWindow` resolves the ref via the existing managers (already in the environment because `WindowGroup(for:)` scenes inherit the app's environment), loads the `PageFile`, and renders `PageEditorView`. The standalone window has its own minimal toolbar (no sidebar, no tab strip) and respects native macOS window tabbing — users who want multiple standalone Pages can `⌥⌘T` to combine them into a tab group via the OS-provided behavior.

##### Why not always-new-window?

Tabs are the discoverable, low-friction default. Notion, Obsidian, Safari, Cursor all converge on this. New windows are the "I need to see two Pages side-by-side without splitting the main window" escape hatch. Forcing every Page into a new window clutters the dock and breaks the mental model of "the Pommora window."

##### Why not always-new-tab?

Side-by-side comparison, dual-monitor workflows, and "I want to keep this Page visible while I work in the main window" are real needs. The `⌥⌘O` shortcut + right-click option costs nothing to add and unlocks those patterns.

##### Implementation order

- **v0.3a** wires `PageEditorView` into the detail-pane dispatcher (`SidebarDetailView`) and adds `WindowGroup(for: PageRef.self)` + `StandalonePageWindow` for the new-window path. Right-click menu item ("Open in New Window") + `⌥⌘O` shortcut + File menu entry land here.
- **v0.4** lifts the detail-pane content into a multi-tab interface. `PageEditorView` becomes one of several tab-mountable content kinds (alongside `VaultDetailView`, `CollectionDetailView`, etc.). The standalone-window path from v0.3a continues to work in parallel.

---

#### v0.3a implementation tasks (prose + standard Markdown)

Pre-flight (must land before v0.3a starts):
1. **v0.2 merged to main** (per `Handoff.md`) — `paradigm-scaffolding` branch lands via `--no-ff` merge preserving full 82-commit history. Baseline for v0.3 work.
2. **v0.2 carryover items** — three CodeRabbit findings from the v0.2 final review are non-blocking for the merge but worth folding into v0.3a's first commit (test infrastructure ContentManager touches anyway):
   - **`ItemWindow.swift:194-204`** — after `renameItem` succeeds, refetch-by-id assumes success. If refetch fails, on-disk rename is out of sync with in-memory state. Fix: force collection-reload + retry, then set `errorMessage` + dismiss if still missing. The same pattern applies to the new `updatePage` flow — apply preventively in `PageEditorViewModel`.
   - **`ContentManagerTests.swift:57-66`** — `renameItem` test asserts in-memory title change but not the filesystem rename. Extend to verify old URL gone + new URL exists. Add the same filesystem-check pattern to new `updatePage` tests.
   - **`ContentManagerTests.swift:83-96`** — `deletes` test asserts in-memory arrays empty but not filesystem deletion. Extend with `FileManager.fileExists` checks. Apply same pattern to any new ContentManager tests.

v0.3a itself, in order:

1. **`ContentManager.updatePage`** — Collection-scoped + vault-root variants. Mirrors `updateItem` shape. Tests for happy-path + validator failure + IO failure surfaces via `pendingError`.
2. **Editor bundle scaffold** — `EditorSource/` folder with package.json, esbuild config, base Tiptap setup: `@tiptap/core` + `@tiptap/starter-kit` (paragraph, heading, list, code, blockquote, hr, history) + `@tiptap/extension-table` + `@tiptap/extension-markdown` (round-trip). Output `Editor/bundle.js` + `bundle.css`. Built artifacts checked in for v0.3a; Run Script phase deferred.
3. **`WKURLSchemeHandler`** registered for `pommora-editor://`. Serves `index.html`, `bundle.js`, `bundle.css` from `Bundle.main.resourceURL/Editor/`.
4. **`PageEditorBridge`** — `WKScriptMessageHandler` decoding the 4 v0.3a messages (init, save, themeUpdate, editorError) into `PageEditorMessages` Codable types.
5. **`PageEditorViewModel`** — `@MainActor @Observable`. Loads `PageFile`, owns the 300ms debounce, calls `ContentManager.updatePage` on save dispatch, surfaces errors via `pendingError`.
6. **`PageEditorView`** — SwiftUI host. Constructs the VM in `.task(id: pageID)`. Renders `WebView` (iOS/macOS 26+ primitive) pointed at `pommora-editor://index.html`.
7. **Apple-native theme** — `PageEditorTheme.swift` converts `Color+Pommora.swift` brand values + SwiftUI semantic colors to a `ThemeTokens` struct; bridged on init + on `\.colorScheme` change.
8. **Bubble menu (floating toolbar)** — Tiptap's `BubbleMenu` extension showing bold/italic/code/link/strikethrough on text selection. Styled to match macOS text-selection menu.
9. **Detail-pane dispatch** — `SidebarDetailView` learns to render `PageEditorView` when the sidebar selection is a `.page(PageMeta)`. Replaces the existing fall-through to a placeholder.
10. **Standalone window scene** — `WindowGroup(for: PageRef.self)` + `StandalonePageWindow`. Right-click context menu on a Page row adds "Open in New Window" + `⌥⌘O` shortcut.
11. **Manual gold-path verification** — create Page → click in sidebar → editor opens in detail pane → type → switch to another Page → switch back → verify body persisted. Open same Page in new window via right-click → edit in one → see saved file on disk → reload other surface (close + reopen for v0.3a; live sync via file watcher is v0.8+).

Out of scope for v0.3a (deferred to v0.3b / v0.3c):
- `:::callout` directive
- `@Columns` directive
- Heading fold UI
- Wikilink rendering, autocomplete, click handling, rename cascade
- Inline image rendering
- Slash menu (deferred to v0.3b with directive insertion)
- Multi-tab editing (deferred to v0.4)
- Property panel UI (deferred to v0.5)

v0.3a ships when standard Markdown (paragraphs, headings, lists, code blocks, GFM tables, blockquotes, hr) round-trips edge-to-edge as WYSIWYG — load `.md`, edit in WYSIWYG view, save, reload, prose-identical (byte-level minor whitespace normalization OK).

---

#### v0.3b + v0.3c outline (defer detailed planning until v0.3a lands)

**v0.3b — Directives + heading fold + slash menu**
- **`:::callout` node** — Tiptap `Node.create` with `markdownTokenizer` matching `/^:::(callout)\n([\s\S]*?)\n:::\n?/` (the Tiptap admonition tutorial is a 1:1 fit). React-free node view rendered as a `<div class="pommora-callout">` with editable inner content. `parseMarkdown` / `renderMarkdown` round-trips via the per-node serializer.
- **`@Columns` node** — `Node.create` with `markdownTokenizer` matching `/^@Columns\n([\s\S]*?)\n@end\n?/` (or `:::columns` for consistency with callouts — to decide). Renders as CSS Grid with child columns; each column is an editable nested editor region.
- **Heading fold** — Tiptap decoration plugin watching heading nodes; chevron rendered next to each heading via `addNodeView`; click toggles a CSS class on the heading + uses `editor.commands.setNodeSelection` to skip past collapsed regions.
- **Slash menu** — Tiptap `Suggestion` plugin triggered on `/` at line start. Popover lists: Callout, Columns, Code block, Heading 1-5, Bullet/Ordered list, Quote, Table, Divider. Filterable by typing.
- **Markdown input rules expanded** — `# `, `## `, `* `, `1. `, `> `, ` ``` ` etc. (these are mostly free from `@tiptap/starter-kit`; v0.3b verifies + polishes per Pommora's defaults).

**v0.3c — Wikilinks**
- **`Wikilink` inline node** — Tiptap `Node.create({ inline: true })` with attrs `{ targetID, displayTitle }`. `renderHTML` outputs `<span class="pommora-wikilink" data-id="...">{displayTitle}</span>`. CSS gives the styled-inline-text look (no chip background). `renderMarkdown` outputs `[[<displayTitle>]]`; `parseMarkdown` resolves `[[Title]]` → ID at parse time via the `query` bridge.
- **Wikilink suggestion plugin** — Tiptap `Suggestion` triggered on `[[`. Popover queries Swift via the `query` bridge message; ContentManager + TopicManager + SpaceManager return matching entries; JS renders the list; selection inserts a `Wikilink` node with `{ targetID, displayTitle }` attrs.
- **Click handler** — clicking a rendered wikilink fires `openWikilink` bridge message with `{ id, kind }`. Swift routes: Page → opens in detail pane (replaces current; tabs land at v0.4); Context → detail pane; Item → ItemWindow popover. Once v0.4 ships, Page → new tab by default.
- **Rename cascade** — `ContentManager.renamePage` runs a body-scan rewrite across all Pages whose body contains `[[<oldTitle>]]` (naive scan in v0.3c; SQLite-indexed version lands with v0.8 Watcher).
- **Inline display refresh** — when a referenced Page is renamed, the wikilink's `displayTitle` updates on next load. (Live update across open editors is v0.8+ file-watcher territory.)

---

#### Risks / open questions

1. **Build-step ergonomics.** Checking the built JS bundle into the repo is the simplest v0.3a approach but bloats diffs. Adding an Xcode Run Script phase that invokes `npx esbuild` adds a Node toolchain dependency. **Recommendation:** check in for v0.3a, add Run Script in v0.3b when the editor bundle starts changing more frequently.
2. **Editor bundle size.** Target <300 KB minified+gzipped for the v0.3a bundle. Tiptap core + markdown extension + starter-kit + table extension lands around ~220 KB; bubble menu + our setup brings it close to the target. If we exceed, audit which `@tiptap/*` extensions we're pulling in — many of starter-kit's pieces are individually importable.
3. **Tab persistence across quit.** v0.4 owns this; v0.3 ships single-Page-in-detail-pane and survives without persistence (the sidebar selection state already restores).
4. **External edit detection.** Spec relies on the v0.8 file watcher. Until v0.8, an external edit isn't reflected until the user navigates away from the Page and back. Document this as expected behavior for v0.3.
5. **WebKit content-security-policy.** Lock the editor's `index.html` to a strict CSP — `default-src 'self' pommora-editor:; img-src 'self' pommora-editor: data:; style-src 'self' pommora-editor: 'unsafe-inline'` — so any future dependency that tries to phone home fails loudly.
6. **macOS 26+ `WebView` primitive maturity.** The WWDC25-introduced `WebView` SwiftUI primitive is new. If it doesn't expose `WKURLSchemeHandler` configuration cleanly, fall back to `NSViewRepresentable` wrapping `WKWebView` — Pallepadehat's package shows this exact pattern. Verify at v0.3a implementation start.
7. **Markdown round-trip edge cases.** Tiptap's `@tiptap/markdown` extension covers standard Markdown well. The two Pommora directives need custom serializers (covered in v0.3b). Edge cases worth verifying with fixture tests during v0.3a: nested lists with mixed markers, tables with empty cells, blockquotes containing code blocks, code blocks with backticks in the content (fence escalation).
8. **Pages without property panel.** v0.3 ships the body editor without the property panel UI (Properties is v0.5). Frontmatter loads + saves intact via `PageFile`, but `tier1`/`tier2`/`tier3` Context relations and per-Vault schema properties aren't editable in-app. Users who need to set Context categorization between v0.3 and v0.5 edit YAML manually in an external text editor. Acceptable trade-off per Nathan's roadmap direction.

---

#### Test approach

The bridge contract makes the editor stack testable without ever spinning up a WKWebView.

**`BridgeProtocol`** — an abstraction wrapping the message-send side of `PageEditorBridge`:

```swift
@MainActor
protocol BridgeProtocol: AnyObject {
    func send(_ message: PageEditorMessage) throws
}
```

Production: `PageEditorBridge` conforms by serializing the message and calling `webView.evaluateJavaScript("window.pommoraEditor.receive(...)")`. Tests: a stub records every `send(_:)` call into an array for assertion.

**`PageEditorViewModel` tests** — never instantiate Tiptap, never load a WKWebView:

```swift
@MainActor
@Test func bodyDidChange_debouncesAndSavesViaContentManager() async throws {
    let bridge = StubBridge()
    let manager = MockContentManager()
    let vm = PageEditorViewModel(page: testMeta, manager: manager, bridge: bridge)

    vm.bodyDidChange("new content")
    try await Task.sleep(for: .milliseconds(350))   // wait past 300ms debounce

    #expect(manager.updatePageCalls.count == 1)
    #expect(manager.updatePageCalls[0].body == "new content")
}

@MainActor
@Test func receivedSaveMessage_routesToBodyDidChange() async throws {
    let vm = PageEditorViewModel(page: testMeta, manager: MockContentManager(), bridge: StubBridge())
    vm.bridge(didReceive: .save(markdown: "edited"))
    #expect(vm.pageFile.body == "edited")
}
```

**Bridge tests** — verify Codable round-trips:

```swift
@Test func saveMessage_decodesFromJSON() throws {
    let json = #"{"type":"save","markdown":"# Hello"}"#.data(using: .utf8)!
    let msg = try JSONDecoder().decode(PageEditorMessage.self, from: json)
    if case .save(let markdown) = msg { #expect(markdown == "# Hello") } else { Issue.record() }
}
```

**Manual gold-path verification** (run after v0.3a code complete):
1. Launch Pommora, pick a nexus
2. Create a Vault → create a Collection → create a Page in the Collection
3. Click the Page row in the sidebar → editor opens in detail pane
4. Type prose: heading, list, code block, blockquote, table
5. Switch to a different Page → switch back → body persisted
6. Open built `.app` package contents, navigate to `Resources/Editor/`, verify `index.html`, `bundle.js`, `bundle.css` present
7. Open the `.md` file in `vim` → verify body matches what's in editor, frontmatter intact
8. Right-click the Page row → "Open in New Window" → standalone window opens with same body
9. Edit in standalone → save → close → reopen main window detail pane → body matches
10. `xcodebuild test -only-testing:PommoraTests` → all tests pass including new VM + bridge tests

---

#### Code skeletons — for fresh-chat implementation

These are signatures and shape, not bodies. They match Pommora's existing patterns (see [ContentManager.swift](Pommora/Pommora/Content/ContentManager.swift), [ItemWindow.swift](Pommora/Pommora/ItemWindow/ItemWindow.swift), [AtomicYAMLMarkdown.swift](Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift) for the conventions to follow).

##### Swift side

```swift
// PageEditorMessages.swift
// All messages between Swift and JS. Codable round-trips both directions.

enum PageEditorMessage: Codable, Equatable, Sendable {
    case `init`(markdown: String, theme: ThemeTokens)            // Swift → JS
    case save(markdown: String)                                  // JS → Swift
    case themeUpdate(theme: ThemeTokens)                         // Swift → JS
    case query(prefix: String)                                   // JS → Swift (v0.3c)
    case queryResults(entries: [WikilinkEntry])                  // Swift → JS (v0.3c)
    case openWikilink(id: String, kind: WikilinkKind)            // JS → Swift (v0.3c)
    case editorError(message: String, fatal: Bool)               // JS → Swift

    // Discriminated union via "type" field: {"type":"save","markdown":"..."}
    // Custom init(from:) + encode(to:) per project Swift 6 convention
    // (any Decoder / any Encoder).
}

struct ThemeTokens: Codable, Equatable, Sendable {
    let accent: String                  // hex e.g. "#7C3AED"
    let codeForeground: String
    let codeBackground: String
    let calloutBorder: String
    let blockquoteBar: String
    let selection: String               // hex with alpha e.g. "#7C3AED40"
    let isDark: Bool                    // for editor to set [data-theme="dark"]
}

struct WikilinkEntry: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: WikilinkKind
    let icon: String?
}

enum WikilinkKind: String, Codable, Sendable {
    case page, context, item
}
```

```swift
// PageEditorBridge.swift
// WKScriptMessageHandler + WKURLSchemeHandler. Decodes inbound messages,
// serializes outbound messages, serves bundle files.

import WebKit

@MainActor
protocol BridgeProtocol: AnyObject {
    func send(_ message: PageEditorMessage) throws
}

@MainActor
final class PageEditorBridge: NSObject, WKScriptMessageHandler, BridgeProtocol {
    weak var viewModel: PageEditorViewModel?
    weak var webView: WKWebView?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let msg = try? JSONDecoder().decode(PageEditorMessage.self, from: data)
        else { return }
        viewModel?.bridge(didReceive: msg)
    }

    func send(_ message: PageEditorMessage) throws {
        let data = try JSONEncoder().encode(message)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.pommoraEditor.receive(\(json))"
        webView?.evaluateJavaScript(js)
    }
}

@MainActor
final class PommoraEditorURLSchemeHandler: NSObject, WKURLSchemeHandler {
    // Serves Bundle.main.resourceURL/Editor/<path> for pommora-editor:// URLs.
    // Maps .html → text/html, .js → application/javascript, .css → text/css.
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) { /* ... */ }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { /* ... */ }
}
```

```swift
// PageEditorViewModel.swift
// @MainActor @Observable. Owns the loaded PageFile + debounce. Mirrors
// the manager pattern in ContentManager.swift.

import Foundation
import Observation

@MainActor
@Observable
final class PageEditorViewModel {
    let pageMeta: PageMeta
    private(set) var pageFile: PageFile
    var pendingError: (any Error)?

    private let manager: ContentManager       // or a `ContentManagerProtocol` for tests
    private let bridge: any BridgeProtocol
    private var saveTask: Task<Void, Never>?

    init(page: PageMeta, manager: ContentManager, bridge: any BridgeProtocol) {
        self.pageMeta = page
        self.pageFile = (try? PageFile.load(from: page.url)) ?? .empty(for: page)
        self.manager = manager
        self.bridge = bridge
    }

    /// Send init message to JS after WebView is ready.
    func didMountEditor(theme: ThemeTokens) {
        try? bridge.send(.`init`(markdown: pageFile.body, theme: theme))
    }

    /// Push theme update without remounting.
    func themeDidChange(_ theme: ThemeTokens) {
        try? bridge.send(.themeUpdate(theme: theme))
    }

    /// Inbound dispatch.
    func bridge(didReceive message: PageEditorMessage) {
        switch message {
        case .save(let markdown):
            bodyDidChange(markdown)
        case .editorError(let msg, let fatal):
            pendingError = EditorError(message: msg, fatal: fatal)
        // v0.3c: .query, .openWikilink
        default:
            break
        }
    }

    /// Debounced save via ContentManager.
    private func bodyDidChange(_ newBody: String) {
        pageFile.body = newBody
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await self.commitSave()
        }
    }

    private func commitSave() async {
        do {
            // Routes through the new ContentManager.updatePage method
            // (added as v0.3a task 1). Variant selection matches PageMeta location.
            try await manager.updatePage(pageFile, meta: pageMeta)
        } catch {
            pendingError = error
        }
    }
}

struct EditorError: LocalizedError {
    let message: String
    let fatal: Bool
    var errorDescription: String? { message }
}
```

```swift
// PageEditorView.swift
// SwiftUI host. Renders WebView pointed at pommora-editor://index.html.
// On macOS 26+, uses the new SwiftUI WebView primitive directly.
// Pre-26 fallback: NSViewRepresentable wrapping WKWebView (see Risks #6).

import SwiftUI
import WebKit

struct PageEditorView: View {
    let page: PageMeta
    @Environment(ContentManager.self) private var contentManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: PageEditorViewModel?
    @State private var bridge = PageEditorBridge()

    var body: some View {
        Group {
            if let vm = viewModel {
                PageEditorWebViewHost(bridge: bridge, viewModel: vm)
                    .onChange(of: colorScheme) { _, _ in
                        vm.themeDidChange(PageEditorTheme.tokens(for: colorScheme))
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: page.id) {
            let vm = PageEditorViewModel(page: page, manager: contentManager, bridge: bridge)
            bridge.viewModel = vm
            viewModel = vm
        }
    }
}

// Wraps WKWebView in NSViewRepresentable. Replace with SwiftUI WebView
// primitive once macOS 26 minimum + WKURLSchemeHandler ergonomics verified.
struct PageEditorWebViewHost: NSViewRepresentable {
    let bridge: PageEditorBridge
    let viewModel: PageEditorViewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PommoraEditorURLSchemeHandler(), forURLScheme: "pommora-editor")
        config.userContentController.add(bridge, name: "pommora")
        let webView = WKWebView(frame: .zero, configuration: config)
        bridge.webView = webView
        webView.load(URLRequest(url: URL(string: "pommora-editor://index.html")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) { /* idempotent */ }
}
```

```swift
// ContentManager.swift extension (NEW in v0.3a task 1)

extension ContentManager {
    /// Update a Page's body + frontmatter on disk. Variant selection
    /// derived from the page's PageMeta (Collection-scoped or vault-root).
    func updatePage(_ file: PageFile, meta: PageMeta) async throws {
        // PageValidator.validate(...) — same shape as updateItem
        // try file.save(to: meta.url) — atomic via AtomicYAMLMarkdown
        // Update in-memory pagesByCollection[id] / pagesByVaultRoot[id]
        // self.pendingError = error on failure
    }
}
```

```swift
// PageRef + scene wiring (in PommoraApp.swift)

struct PageRef: Hashable, Codable {
    let pageID: String
    let vaultID: String
    let collectionID: String?
}

@main
struct PommoraApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }

        WindowGroup(for: PageRef.self) { $ref in
            if let ref { StandalonePageWindow(ref: ref) }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings { SettingsView() }
    }
}
```

##### TypeScript side (`EditorSource/`)

```json
// package.json
{
  "name": "pommora-editor",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "node esbuild.config.mjs",
    "watch": "node esbuild.config.mjs --watch"
  },
  "dependencies": {
    "@tiptap/core": "^2.x",
    "@tiptap/pm": "^2.x",
    "@tiptap/starter-kit": "^2.x",
    "@tiptap/extension-table": "^2.x",
    "@tiptap/extension-table-row": "^2.x",
    "@tiptap/extension-table-cell": "^2.x",
    "@tiptap/extension-table-header": "^2.x",
    "@tiptap/extension-bubble-menu": "^2.x",
    "@tiptap/markdown": "^2.x"
  },
  "devDependencies": {
    "esbuild": "^0.21.x",
    "typescript": "^5.x"
  }
}
```

```javascript
// esbuild.config.mjs
import { build, context } from 'esbuild'

const config = {
  entryPoints: ['src/main.ts'],
  bundle: true,
  format: 'esm',
  target: 'safari17',          // matches macOS Sonoma+ WebKit
  outfile: '../Editor/bundle.js',
  minify: true,
  sourcemap: true,
  loader: { '.css': 'text' },
}

if (process.argv.includes('--watch')) {
  const ctx = await context(config)
  await ctx.watch()
} else {
  await build(config)
}
```

```html
<!-- Editor/index.html — minimal mount point, strict CSP -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'self' pommora-editor:; img-src 'self' pommora-editor: data:; style-src 'self' pommora-editor: 'unsafe-inline'">
  <link rel="stylesheet" href="pommora-editor://bundle.css">
</head>
<body>
  <div id="editor"></div>
  <script type="module" src="pommora-editor://bundle.js"></script>
</body>
</html>
```

```typescript
// EditorSource/src/main.ts
// Entry point. Wires Tiptap with selected extensions and the bridge.

import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Table from '@tiptap/extension-table'
import TableRow from '@tiptap/extension-table-row'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import BubbleMenu from '@tiptap/extension-bubble-menu'
import { Markdown } from '@tiptap/markdown'

import { setupBridge, sendSave } from './bridge'
import { applyTheme } from './theme'

const editor = new Editor({
  element: document.getElementById('editor')!,
  extensions: [
    StarterKit,
    Table.configure({ resizable: false }),
    TableRow,
    TableCell,
    TableHeader,
    BubbleMenu.configure({ /* anchor element + buttons */ }),
    Markdown.configure({ html: false, transformPastedText: true }),
  ],
  content: '',
  onUpdate: debounce(({ editor }) => {
    sendSave(editor.storage.markdown.getMarkdown())
  }, 200),
})

// Bridge wires window.pommoraEditor.receive() to dispatch messages
// from Swift (init, themeUpdate, queryResults).
setupBridge({
  onInit: ({ markdown, theme }) => {
    applyTheme(theme)
    editor.commands.setContent(markdown, { contentType: 'markdown' })
  },
  onThemeUpdate: ({ theme }) => applyTheme(theme),
})
```

```typescript
// EditorSource/src/bridge.ts
// Thin wrapper around window.webkit.messageHandlers.pommora.

type IncomingMessage =
  | { type: 'init', markdown: string, theme: ThemeTokens }
  | { type: 'themeUpdate', theme: ThemeTokens }
  | { type: 'queryResults', entries: WikilinkEntry[] }

interface BridgeHandlers {
  onInit: (msg: Extract<IncomingMessage, { type: 'init' }>) => void
  onThemeUpdate: (msg: Extract<IncomingMessage, { type: 'themeUpdate' }>) => void
}

export function setupBridge(handlers: BridgeHandlers) {
  ;(window as any).pommoraEditor = {
    receive: (msg: IncomingMessage) => {
      switch (msg.type) {
        case 'init': handlers.onInit(msg); break
        case 'themeUpdate': handlers.onThemeUpdate(msg); break
      }
    }
  }
}

export function sendSave(markdown: string) {
  postToSwift({ type: 'save', markdown })
}

function postToSwift(msg: object) {
  ;(window as any).webkit.messageHandlers.pommora.postMessage(JSON.stringify(msg))
}
```

```css
/* Editor/bundle.css — Apple-native baseline. Loaded into the editor canvas. */
:root {
  --pommora-accent: #7C3AED;
  --pommora-code-fg: #FF2525;
  --pommora-code-bg: #323233;
  --pommora-callout-border: #444;
  --pommora-blockquote-bar: #888;
  --pommora-selection: rgba(124, 58, 237, 0.25);
}

html, body {
  margin: 0;
  padding: 0;
  background: transparent;
  color-scheme: light dark;
}

#editor {
  font-family: -apple-system, BlinkMacSystemFont, system-ui;
  font: -apple-system-body;
  line-height: 1.55;
  padding: 24px 48px;
  max-width: 760px;
  margin: 0 auto;
}

#editor code, #editor pre {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 1em;
  line-height: 1.45;
}

#editor :not(pre) > code {
  color: var(--pommora-code-fg);
  background: var(--pommora-code-bg);
  padding: 0.1em 0.3em;
  border-radius: 3px;
}

#editor pre {
  background: var(--pommora-code-bg);
  padding: 12px 16px;
  border-radius: 6px;
}

#editor blockquote {
  /* Apple Calendar event-card pattern: filled bg + left bar, no border */
  background: rgba(128, 128, 128, 0.12);
  border-left: 3px solid var(--pommora-blockquote-bar);
  padding: 8px 14px;
  border-radius: 4px;
  margin: 0.5em 0;
}

#editor .pommora-callout {
  /* Distinct from blockquote: outlined box, transparent bg */
  border: 1px solid var(--pommora-callout-border);
  border-radius: 6px;
  padding: 12px 16px;
  margin: 0.5em 0;
}

::selection {
  background: var(--pommora-selection);
}

/* Bubble menu (Tiptap BubbleMenu styled native) */
.tippy-box[data-theme~="pommora"] {
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(20px);
  border: 1px solid rgba(0, 0, 0, 0.1);
  border-radius: 6px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}
```

---

#### References

- **Tiptap** ([tiptap.dev](https://tiptap.dev/), [docs](https://tiptap.dev/docs/editor), [GitHub](https://github.com/ueberdosis/tiptap)) — MIT, ProseMirror-based, headless. The `@tiptap/markdown` extension provides `parseMarkdown` / `renderMarkdown` per-node round-trip.
- **Tiptap "Notion-like editor" demo** ([tiptap.dev](https://tiptap.dev/)) — visual confirmation of the chrome model Pommora wants: quiet prose flow, floating toolbar on selection, `/` slash menu, no always-visible block UI.
- **Tiptap admonition tutorial** ([docs.tiptap.dev create-a-admonition-block](https://github.com/ueberdosis/tiptap-docs/blob/main/src/content/editor/markdown/guides/create-a-admonition-block.mdx)) — 1:1 template for `:::callout`.
- **MarkEdit** ([repo](https://github.com/MarkEdit-app/MarkEdit), MIT, ~3.3k★) — production reference for the WKWebView + native-shell pattern (the shell is reused; the editor engine is swapped from MarkEdit's CodeMirror to Pommora's Tiptap).
- **WWDC25 Session 280 — Cook up a rich text experience in SwiftUI with AttributedString** ([video](https://developer.apple.com/videos/play/wwdc2025/280/)) — informs the property-panel surface; doesn't drive the editor canvas itself.
- **Pages.md** — the spec this plan implements.
- **Resources.md** — editor candidate catalog.
- **UIX-Guide.md** — SwiftUI conventions for the surrounding shell.
