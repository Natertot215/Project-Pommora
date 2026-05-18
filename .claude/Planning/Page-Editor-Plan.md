### Page Editor — Options Inventory

Catalogs the three editor approaches surfaced during the v0.2.7 prep research session. Pure inventory — no recommendation, no implementation plan. Selection happens separately; the plan doc for the chosen option lives downstream of this one.

All three options write and read the same `.md` files Pommora already stores. The on-disk format is the architectural firewall — switching options later doesn't migrate user data.

---

#### Option 1 — Native Swift (swift-markdown + TextKit 2)

A SwiftUI-hosted `NSTextView` running TextKit 2 as the layout engine, with `swift-markdown` driving the parse tree that informs attribute decoration. No WebKit. No JavaScript. The editor lives entirely in the Swift module.

##### Building blocks available

- **`swift-markdown`** ([github.com/swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown)) — Apple's official CommonMark parser, powered by cmark-gfm. Full GFM (tables, strikethrough, task lists, autolinks). Immutable, thread-safe, copy-on-write value-type AST. `MarkupWalker` / `MarkupVisitor` protocols for traversal. **Source-range tracking** (`element.range.lowerBound.line/column/source`) — required for cursor-aware decoration. `Table` is a first-class AST node with column alignments, header, body. Programmatic `Document(...)` construction. `HTMLFormatter` built in. Used in production by DocC. No first-class custom-directive API — `:::callout` and `@Columns` would require post-parse traversal or a sibling parser layer.

- **TextKit 2** — `NSTextLayoutManager` + `NSTextContentManager` + `NSTextElement` + `NSTextViewportLayoutController`. Viewport-based non-contiguous layout (renders only visible fragments). `NSTextAttachmentViewProvider` (macOS 13+) hosts SwiftUI/AppKit views inside the text flow. Attribute-based hiding (Apple Developer Forums confirmation): subclass `NSTextLayoutFragment` and ignore hidden ranges during draw, or use zero-width/alpha-0 attributes. Cursor-aware decoration via `NSTextViewDelegate` selection observation + `performEditingTransaction(_:)`.

- **WWDC25 Session 280 — `TextEditor(text: AttributedString)`** — macOS 26+. Character-level rich text (bold/italic/underline/strikethrough/fonts/colors/paragraph styles/Genmoji). Mutation via `transform(updating:)` preserves selection indices. Custom attributes extensible via `AttributedTextFormattingDefinition`. Not extensible for custom inline nodes or block containers.

##### Reference implementation

**`nodes-app/swift-markdown-engine`** ([github.com/nodes-app/swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)) — open-source. Apache 2.0. 455★. v0.4.0 May 2026. macOS 14+, Swift 5.9+. Pre-1.0; API may change between minor releases. Built by Nodes (Germany) and shipping in their commercial Nodes macOS app.

Ships out of the box: `NativeTextViewWrapper(text: $text)` SwiftUI wrapper; live Markdown styling (bold, italic, headings, lists, code, links, task checkboxes, rules); **wiki-style linking with `[[Name|<id>]]` storage/display round-trip** (matches Pommora's wikilink spec); image embeds via `![[Name]]`; LaTeX blocks (`$$`) and inline (`$`); code blocks with embedder-supplied syntax highlighting; Writing Tools integration (macOS 15.1+); spelling & grammar with code/LaTeX/wiki-link suppression; bottom overscroll; drag-select autoscroll.

Not shipped: tables, multi-column layout, block-level callouts.

##### Known framework gaps

- **No native `NSTextTable` in TextKit 2.** If the attributed string contains an actual `NSTextTable` instance, TextKit 2 falls back to TextKit 1, which disables `NSTextAttachmentViewProvider`. Catch-22 documented on Apple Developer Forums (thread 776824). Workaround: render tables via `NSTextAttachment` / `NSTextAttachmentViewProvider` (custom view), never via `NSTextTable` — the fallback isn't triggered by "the document contains table syntax," only by "the attributed string contains an `NSTextTable` instance."

- **No multi-column inline layout API in TextKit 2.** Multiple `NSTextContainer`s is the TextKit 1 approach; doesn't fit single-document flow. `@Columns` requires custom rendering — STTextView discussions note custom `NSTextContentManager` is "challenging" and "requires a lot of work with many unclear details."

- **Heading folding has no built-in API.** Custom attribute-based hiding via `NSTextStorage` ranges marked visually invisible. Swift Forums thread 8487 notes "mostly unfruitful" for sample code; pattern is established but bespoke per app.

- **`swift-markdown` lacks first-class custom-directive parsing.** Post-parse traversal or a regex-based sibling pass handles `:::callout` / `@Columns`.

##### Native-feel inheritance

`NSTextView` inherits without effort: macOS caret, selection color (`NSColor.selectedTextBackgroundColor`), scroll physics, Look Up, Services menu, Dictation, Writing Tools (macOS 15.1+), accessibility, spell-check, system text-replacement.

---

#### Option 2 — JS editor library inside a macOS shell we build

A `WKWebView` hosting an off-the-shelf JS Markdown editor (Tiptap, Milkdown, or another library), wrapped in a macOS shell we author. The editor library handles standard Markdown editing out of the box — paragraphs, headings, lists, code, tables, marks, history, etc. The shell layer (WKWebView wrapper, Swift↔JS bridge, build pipeline, HTML host page) and the Pommora-specific extensions are what we write.

The shell layer is standard WebKit work — well-documented patterns, no research required. Pallepadehat's shell is ~600 LOC Swift + ~500 LOC TypeScript + a `bun`/`vite` setup, which corresponds to roughly 1–2 Claude sessions to set up cleanly. As of this session's research (May 2026), no Swift Package equivalent to Pallepadehat exists for Tiptap, Milkdown, or BlockNote, so the shell isn't inherited as it is in Option 3 — but the shell itself isn't where the meaningful cost lives.

##### Available editor libraries (off-the-shelf, npm-installed)

- **Tiptap** ([tiptap.dev](https://tiptap.dev/)) — ProseMirror-based, vanilla TypeScript, MIT. ~250 KB minified+gzipped for core + markdown + selected extensions. WYSIWYG-first; headless (no opinion on chrome). `@tiptap/markdown` for parse/render round-trip per node. `Node.create` + `markdownTokenizer` for custom directives. Tables first-class via `@tiptap/extension-table`. Bubble menu via `@tiptap/extension-bubble-menu`. Slash-menu pattern via `@tiptap/suggestion`. History (undo/redo) built in. Production-proven (Notion-likes, GitHub web editor).

- **Milkdown** — ProseMirror + remark, MIT. ~400 KB. Better Markdown round-trip fidelity than Tiptap. `containerDirective` via remark-directive for `:::callout`-style syntax. Comparable extension model to Tiptap.

- **BlockNote** — React-based, MPL-2.0 core / GPL-3.0 or commercial Business for multi-column extension. Block-on-every-paragraph UI by default. (React dependency adds ~150 KB.)

- **CodeMirror 6** — MIT. Source-with-decorations (Live Preview / source-mode pattern). Mature widget/decoration model. Built-in code folding (`@codemirror/language` `foldNodeProp`), search panel (`@codemirror/search`), virtual scrolling. Note: Option 3 covers the CodeMirror path with a pre-built shell, so Option 2 with CodeMirror only makes sense if Pallepadehat's shell is specifically rejected.

##### Off-the-shelf for free (what the editor library provides)

Standard Markdown editing — paragraphs, headings, lists, blockquotes, inline marks (bold/italic/code/strikethrough), fenced code blocks, horizontal rules, links, images, history (undo/redo), keyboard shortcuts. Tables (where the library supports them). The library's extension API for adding custom nodes/marks. The library's documentation, community, and ecosystem.

##### macOS shell we build (1–2 sessions)

Standard WebKit patterns, no research required:

- `WKWebView` configuration: `websiteDataStore = .nonPersistent()` + `mediaTypesRequiringUserActionForPlayback = .all`.
- Either `webView.loadFileURL(_:allowingReadAccessTo:)` (Pallepadehat's choice — simplest), or `WKURLSchemeHandler` for a custom scheme if [WebKit bug #154916](https://bugs.webkit.org/show_bug.cgi?id=154916) bites (`file://` null origin blocks `<script type="module">`).
- `WKScriptMessageHandler` bridge with Codable message types for save/init/themeUpdate/wikilink-query/openWikilink/editorError. Validation + JS-injection escaping. `LeakAvoider`-style retain-cycle prevention.
- npm/bun + Vite + TypeScript build pipeline. Single-file bundle via `vite-plugin-singlefile` produces one `editor.html` that ships as an SPM Resource.
- HTML host page (`index.html`), strict CSP if needed.
- Theme bridge: Pommora brand tokens from `Color+Pommora.swift` mapped to CSS custom properties on init + on `colorScheme` change.
- App Sandbox: requires Outgoing Connections (Client) for WKWebView XPC.

The bulk of Option 2's work isn't here — it's in the Pommora-specific extensions below, which is roughly the same effort whichever option you pick.

##### Pommora-specific extensions we'd write

Inside the editor library's extension model: `:::callout`, `@Columns`, wikilink inline node (with `[[`-triggered Suggestion plugin querying Swift via the bridge), wikilink click handling, heading fold (if not built into the library), bubble-menu button set, slash-menu command list.

##### Native-feel approximation

Approximated through CSS: `font-family: -apple-system, BlinkMacSystemFont, "SF Mono", Menlo, monospace;`; `font: -apple-system-body;` text styles; `::selection { background: var(--pommora-selection); }` matching `NSColor.selectedTextBackgroundColor`; WebKit's default caret; no custom focus shadows.

Scroll physics is WebKit's, not AppKit's — the documented UX seam (MarkEdit accepts the same trade-off).

---

#### Option 3 — Fork MarkdownEditor (CodeMirror 6 + WKWebView, ours after fork)

Structurally the same pattern as Option 2 — a JS editor inside a WKWebView shell — except the shell is **already built** as a Swift Package: [github.com/Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor). MIT. v1.0.1 (Feb 11 2026). 26★, 6 forks. macOS 14+, Swift 5.9+, Xcode 15+. 3,010 LOC total (~1,300 Swift, ~1,700 TypeScript).

We fork into a Pommora-owned repo (e.g., `pommora/MarkdownEditor`) so the code is ours; Pommora's SPM dependency points at the fork URL. Upstream is reference only. The JS editor library is fixed to CodeMirror 6 — this is the only mature pre-built shell-as-a-package we found for any of the candidate libraries.

##### What ships in the package

**Architecture:** `WKWebView` hosting CodeMirror 6. TypeScript core built by Vite + `vite-plugin-singlefile` into a single `editor.html` Resource shipped inside the Swift Package. The pre-built bundle is what consumers load — `bun`/`vite`/`@codemirror/*` only matter when modifying the editor itself.

**Swift API:**

- `EditorWebView(text: Binding<String>, configuration: EditorConfiguration, onReady: (() -> Void)?)` — SwiftUI `NSViewRepresentable`. Two-way `Binding<String>` to the Markdown content. `MarkdownEditorView` type alias.

- `EditorBridge` (`@MainActor final class`) with methods: `setContent` / `getContent` / `setSelection` / `getSelection` / `toggleBold` / `toggleItalic` / `toggleCode` / `toggleStrikethrough` / `insertLink(url:title:)` / `insertImage(url:alt:)` / `insertHeading(level:)` / `insertBlockquote` / `insertCodeBlock(language:)` / `insertList(ordered:)` / `insertHorizontalRule` / `insertDate(format:)` / `insertTimestamp(includeTime:locale:)` / `focus` / `blur` / `undo` / `redo` / `setTheme` / `setFontSize` / `setLineHeight` / `setFontFamily` / `updateConfiguration`.

- `EditorBridgeDelegate` (`@MainActor` protocol) with optional methods: `editorDidChangeContent(_:)` / `editorDidChangeSelection(_:)` / `editorDidBecomeReady()` / `editorDidFocus()` / `editorDidBlur()`.

- `EditorConfiguration` (Codable, Equatable, Sendable): `fontSize`, `fontFamily` (default `-apple-system, BlinkMacSystemFont, "SF Mono", Menlo, Monaco, monospace`), `lineHeight`, `showLineNumbers`, `wrapLines`, `renderMermaid`, `renderMath`, `renderImages`, **`hideSyntax`** (Obsidian Live Preview marker-fade on inactive lines).

- `EditorMessageType`, `EditorSelection`, `EditorTheme` (`.light`/`.dark`, auto-following system), `EditorBridgeError`. `LeakAvoider` prevents the `WKWebView` ↔ message-handler retain cycle.

**TypeScript bundle includes:**

- CodeMirror 6 + `@codemirror/lang-markdown` + `@lezer/markdown` GFM extension. **Tables, strikethrough, task lists all parsed correctly** — the parse tree exposes them; current package doesn't render tables as visual grids.

- `syntax-hiding.ts` (185 LOC) — Obsidian-style Live Preview. Hides `HeaderMark` / `EmphasisMark` / `StrikethroughMark` / `QuoteMark` / `LinkMark` / `ImageMark` / `CodeMark` / `URL` on lines without an active selection range. Uses `Decoration.mark({class: "cm-syntax-hidden"})` with CSS `font-size: 0; opacity: 0` to avoid cursor positioning issues. Active-line cache scoped to the current `EditorState`.

- `command-palette/` (~500 LOC) — `/`-triggered popover with sections: Formatting (Bold, Italic, Strikethrough, Code), Headings (H1–H3), Lists (Bullet, Numbered, Task), Blocks (Quote, Code Block, Divider), Media (Link, Image), Diagrams (Mermaid variants), Math (LaTeX presets), Insert (Date, Time, Timestamp). Commands are a flat `CommandItem[]` array extended by appending.

- `math.ts` (386 LOC) — KaTeX rendering for `$...$` inline and `$$...$$` block.

- `mermaid.ts` (281 LOC) — Mermaid diagrams (flowchart / sequence / class / mindmap variants with starter scaffolds).

- `images.ts` (208 LOC) — inline image rendering with resize handles.

- `extensions/calc.ts` (97 LOC) — smart calculator: typing `$2+2=` evaluates to `4` inline.

- `@uiw/codemirror-theme-xcode` — Xcode-inspired light + dark themes, auto-switching with system appearance.

- `@codemirror/search` — built-in Cmd-F search/replace panel.

- `keymaps.ts` (52 LOC) — keyboard shortcuts (⌘B, ⌘I, ⌘K, etc.).

- Performance: LRU widget caching, theme-aware widgets, lazy loading of Mermaid + KaTeX (22% bundle size reduction).

- `PrivacyInfo.xcprivacy` resource. Tests: `EditorBridgeTests`, `PerformanceTests`, `JavaScriptUtilitiesTests`, `MarkdownEditorTests`. GitHub Actions CI.

- App Sandbox: requires Outgoing Connections (Client) entitlement; Allow JIT in Hardened Runtime if needed.

##### What the package doesn't include

- Wikilink parsing / decoration / `[[`-triggered autocomplete.
- `:::callout` / `@Columns` / arbitrary directive widgets.
- Tables rendered as visual grids (parsed via GFM but shown as syntax-highlighted source).
- Heading fold UI (CodeMirror has `@codemirror/language` `foldNodeProp` and `foldGutter` built in; package doesn't enable them).
- Bubble menu on selection (selection events are bridged to Swift via `editorDidChangeSelection` but no JS floating toolbar).
- Pommora brand theme (only Xcode-inspired themes ship).
- Per-document state memory (cursor position, scroll position).

##### Widget extension pattern

Adding any of the missing features follows the pattern used by the four shipped widgets:

1. Walk the syntax tree: `syntaxTree(state).iterate({ enter: (node) => { ... } })`.
2. For each matching node, add a `Decoration.mark({class: "..."})` (inline CSS class) or `Decoration.replace({widget: new WidgetType()})` (DOM widget) to a `RangeSetBuilder<Decoration>`.
3. Provide the resulting `DecorationSet` as a `StateField` via `EditorView.decorations.from(field)`.
4. Wrap in an `Extension` and expose it through a `Compartment` for dynamic on/off via `updateConfiguration`.

Each new file lives at `CoreEditor/src/widgets/<name>.ts` and wires through `core/editor.ts`. The fork builds via `bun run build` in `CoreEditor/`, producing a new `editor.html` Resource for the Swift Package.

##### Native-feel approximation

Same approximation pattern as Option 2: CSS `-apple-system` default font (already set by the package), Xcode theme matches system appearance, WebKit's caret + scroll physics. Same documented seam.

---

#### Swap costs

`.md` file format is identical across all three options. `ContentManager.updatePage` Swift signature is editor-agnostic. Pommora's frontmatter handling stays Swift-side regardless of option. So a swap is bounded to the editor wrapper + any editor-specific JS/Swift code we authored.

Estimates below are in Claude sessions. A session = ~1–4 hours of focused implementation including tests + review pass.

| From → To | What changes | Claude sessions |
|---|---|---|
| **1 → 2** | Rip out native NSTextView wrapper. Stand up shell (1–2 sessions). Port any native widgets to chosen JS editor lib's extension model. | 1–2 sessions for the shell + 1 session per ported widget |
| **1 → 3** | Rip out native NSTextView wrapper. Add Pallepadehat fork as SPM dep. Wrap `EditorWebView` in `PageEditorView`. Port any native widgets to CodeMirror's decoration model. | 1 session for the swap + 1 session per ported widget |
| **2 → 1** | Rip out shell + bundle. Wrap `nodes-app/swift-markdown-engine` or build native from `swift-markdown` + `NSTextView` + TextKit 2. Port any JS extensions to native decorations. | 1–2 sessions for the swap + 1 session per ported widget |
| **2 → 3** | If using Tiptap/Milkdown/BlockNote: rip out hand-built shell + extensions; add Pallepadehat fork as SPM dep; port custom extensions to CodeMirror's decoration model. If using CodeMirror in a hand-built shell: replace the shell only. | 1 session for the swap + 1 session per ported widget |
| **3 → 1** | Rip out Pallepadehat dep. Wrap `nodes-app/swift-markdown-engine` or build native. Reimplement any fork widgets as native decorations. | 1–2 sessions for the swap + 1 session per ported widget |
| **3 → 2** | Rip out Pallepadehat dep. Stand up hand-built shell + chosen JS lib + extensions. Port any fork widgets to that lib's extension model. | 1–2 sessions for the shell + 1 session per ported widget |

Reversibility is roughly symmetric across all transitions. The shell layer is small (1–2 sessions) regardless of direction; the actual cost in any swap is **per-widget porting**, which is the same work the widgets needed in the first place. Pommora's data is portable across all transitions.
