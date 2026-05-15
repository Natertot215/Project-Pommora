### Pommora — Resources

Catalogue of external resources (documentation, libraries, references) to consult during research and implementation. Items are listed for reference; not all are committed dependencies.

---

#### Editor primitives

The JS editor candidates below are evaluated for the SwiftUI Option 2 path (WKWebView hosting the editor); under Option 1 (native NSTextView) only `apple/swift-markdown` and STTextView apply.

For React-side editor candidates inside WKWebView Option 2, see `// ReactInfo// Editor.md` and `// ReactInfo// Resources.md`.

##### Co-primary candidates

- **BlockNote** — open-source MPL-2.0 core; batteries-included block editor built on top of Tiptap. Slash menu, formatting toolbar, drag handles, schema enforcement all wired by default. [Docs](https://www.blocknotejs.org/docs) · [Custom blocks guide](https://www.blocknotejs.org/docs/features/custom-schemas/custom-blocks) · [Slash menu](https://www.blocknotejs.org/docs/slash-menu) · [Theming](https://www.blocknotejs.org/docs/react/styling-theming/themes) · [Pricing / licensing](https://www.blocknotejs.org/pricing) · [GitHub](https://github.com/TypeCellOS/BlockNote)

  - **License note:** core is MPL-2.0 (open source, OSI-approved); the "XL" packages (`xl-multi-column`, `xl-pdf-exporter`, `xl-docx-exporter`, AI commands) are GPL-3.0 OR a paid commercial Business subscription (specific price not pinned in current docs — verify on blocknotejs.org/pricing). Pommora's project license determines whether `xl-multi-column` can be used directly or must be built custom in BlockNote core.

- **Tiptap** — MIT-licensed open-source editor framework. The headless ProseMirror-React framework BlockNote is built on; anything BlockNote ships can be built on Tiptap directly (with more wiring, more configurability). Every package Pommora would use — `@tiptap/core`, `@tiptap/react`, `@tiptap/extension-drag-handle-react`, `@tiptap/markdown`, all the node / mark / functionality extensions — ships from the regular `@tiptap/*` npm scope under MIT. (Tiptap also sells optional paid extensions for hosted Cloud / AI / Collaboration / Comments services; those live under a separate `@tiptap-pro/*` scope on a private registry and are not relevant to Pommora.) [Docs](https://tiptap.dev/docs/editor) · [Markdown extension](https://tiptap.dev/docs/editor/markdown) · [Drag handle](https://tiptap.dev/docs/editor/extensions/functionality/drag-handle-react) · [GitHub](https://github.com/ueberdosis/tiptap)

##### Pivot doors (kept open, not committed)

- **Milkdown** — MIT, ProseMirror foundation, markdown-first by design (round-trip enforced at the framework level). [Docs](https://milkdown.dev/) · [Styling guide](https://milkdown.dev/docs/guide/styling) · [Crepe API](https://milkdown.dev/docs/api/crepe) · [Plugin awesome list](https://github.com/Milkdown/awesome) · [GitHub](https://github.com/Milkdown/milkdown)

- **Yoopta-Editor** — MIT, Slate-based, 20+ built-in plugins including a callout. [Site](https://yoopta.dev/) · [Docs](https://docs.yoopta.dev/) · [Callout plugin](https://github.com/yoopta-editor/Yoopta-Editor/blob/master/packages/plugins/callout/README.md) · [GitHub](https://github.com/yoopta-editor/Yoopta-Editor)

- **CodeMirror 6** — buffer-based editor (markdown literally *is* the document; round-trip is perfect by definition). Used as Obsidian Live Preview's foundation: `StateField` parses markdown, `Decoration.replace` swaps source ranges with `WidgetType` block widgets. [Docs](https://codemirror.net/) · [GitHub](https://github.com/codemirror/dev)

##### Editor research notes

- **Serialization architecture.** Pommora uses two serialization formats deliberately, each chosen for what it does best: **Markdown** (`.md` on disk) is the canonical content format for every Page; **JSON** (in-memory) is the editor's perfect-fidelity working store for editor state, undo / redo, and any case where Markdown can't carry the information. **BlockNote API:** `blocksToMarkdownLossy(blocks)` / `tryParseMarkdownToBlocks(md)` for the Markdown boundary; `editor.document` for the JSON store; per-block `toExternalHTML` / markdown handlers for the two directives ([Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426)). **Tiptap API:** `@tiptap/markdown` for the Markdown boundary; `editor.getJSON()` for the JSON store; per-node `renderHTML` + custom serializer for the two directives. Both formats are first-class and necessary — Markdown alone can't carry editor state; JSON alone breaks agent-legibility. See `// ReactInfo// Editor.md` for the full architecture.

- **Milkdown / Yoopta / CodeMirror 6** follow the same pattern with different internal stores (ProseMirror state, Slate JSON, CodeMirror's `EditorState`). The Markdown ↔ working-state split is a property of every modern editor framework; the pattern survives an editor pivot, only the API names and boundary code change.

---

#### Editor + parsing

- **Apple swift-markdown** — Markdown parser + AST. Block directives use DocC `@Name(args){}` syntax (NOT Pandoc `:::`). [GitHub](https://github.com/swiftlang/swift-markdown)
- **STTextView** — TextKit 2 NSTextView replacement with a SwiftUI shim (`STTextViewSwiftUI`). Useful for line-number gutters, programmatic decoration insertion, multi-cursor, custom selection rendering. [GitHub](https://github.com/krzyzanowskim/STTextView)
- **[Shpigford/clearly](https://github.com/Shpigford/clearly)** — native AppKit / SwiftUI markdown editor for macOS. Working source-with-decorations editor with a syntax highlighter, fold-state plumbing, and editor shell. Fork-candidate for Pommora's SwiftUI Option 1 (native editor). License: FSL-1.1-MIT (converts to MIT Feb 2028).
- **[Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor)** — Swift Package wrapping CodeMirror 6 in WKWebView with a clean SwiftUI API (`EditorWebView(text: $markdown)`). Ships with Obsidian-style syntax hiding built in, GFM tables, SF fonts by default, light/dark theme, and a command palette triggered by `/`. Key candidate for Option 2 (WKWebView-based editor). Missing for Pommora: `:::callout`, `:::columns`, wikilinks (addable as CM6 extensions). Personal project, one contributor — recommend forking rather than depending. MIT license. [GitHub](https://github.com/Pallepadehat/MarkdownEditor)

#### Spaces (drag-and-drop blocks)

- **stevengharris/SplitView** — nestable resizable splits with persistence. [GitHub](https://github.com/stevengharris/SplitView)

- **visfitness/reorderable** — pure SwiftUI `ReorderableVStack` / `HStack`. [GitHub](https://github.com/visfitness/reorderable)

- **SwiftUIX** — large SwiftUI gap-filler (text views, scroll behavior, AppKit bridges). [GitHub](https://github.com/SwiftUIX/SwiftUIX)

#### State, data, file watching

- **GRDB.swift v7.5+** — SQLite for Swift; FTS5 first-class via `FTS5Pattern`; `ValueObservation.tracking { db in ... }` is the reactive primitive — `.values(in:)` returns an `AsyncThrowingStream` (Swift 6 idiom over Combine). Requires Swift 6.1+/Xcode 16.3+. [GitHub](https://github.com/groue/GRDB.swift)

- **@Observable macro** (Swift 5.9+, mature in 6.2) — non-negotiable for new SwiftUI code; per-property tracking eliminates wasteful redraws; `@State` replaces `@StateObject`. [Apple docs](https://developer.apple.com/documentation/observation)

- **SwiftData** — wraps Core Data; can't use a custom SQLite schema or FTS5 directly. Still not safe for Pommora's "files canonical + custom schema" shape in 2026. **Skip in favor of GRDB.**

- **EonilFSEvents** (or hand-rolled `FSEventStreamCreate`) — nexus folder watching. `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool. Same APFS / atomic-rename gotchas apply: editor atomic-save (write `.tmp` + rename) emits create+delete for the temp; debounce 50–100ms by path; track outbound mtimes to ignore your own writes. [EonilFSEvents on GitHub](https://github.com/eonil/FSEvents)

- **TestFlight for Mac** — fully shipped (post-2021); same capabilities as iOS, internal/external tester model, builds expire after 90 days. [Apple Developer](https://developer.apple.com/testflight/)

#### Mac OS integration (first-party APIs)

Areas where SwiftUI is first-party where Electron has either ceilings or companion-bundle workarounds.

- **CoreSpotlight** — `CSSearchableItem` + `CSSearchableItemAttributeSet`; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links results back into the app.
[Apple docs](https://developer.apple.com/documentation/corespotlight)

- **QuickLook Preview Extension** — ship a `QLPreviewProvider` subclass;
declare `QLSupportedContentTypes` for `net.daringfireball.markdown`. Renders Pommora pages straight from Finder via spacebar. [Apple docs](https://developer.apple.com/documentation/quicklook)

- **NSServices** — declare in `Info.plist`, implement selector; e.g. "New Pommora Page from Selection". [Edenwaith guide](https://www.edenwaith.com/blog/index.php?p=133)

- **Share Extension** — receive shares from Safari/Mail/etc. into Pommora. Add a Share Extension target conforming to `NSExtensionPrincipalClass`. [Apple docs](https://developer.apple.com/documentation/foundation/nsextensionrequesthandling)

- **MenuBarExtra** (macOS 13+) — first-party menu-bar item; `.menuBarExtraStyle(.window)` enables rich popovers. [Apple docs](https://developer.apple.com/documentation/swiftui/menubarextra)

- **NSVisualEffectView via SwiftUI `Material`** — sidebar vibrancy / system materials. [Apple docs](https://developer.apple.com/documentation/swiftui/material)

- **Transferable + `.draggable` / `.dropDestination`** — Finder file-promise drag-out and drag-in. [Apple docs](https://developer.apple.com/documentation/coretransferable/transferable)

- **`.onOpenURL` + `Info.plist` `CFBundleURLTypes`** — `pommora://` deep links. [Apple docs](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))

---

#### Reference and learning tools

- **Interactful** — App Store reference app by Harley Thomas; interactive SwiftUI demos with copy-pasteable code. Useful as a desk-side learning tool while building. [App Store](https://apps.apple.com/us/app/interactful/id1528095640) · [hdthomas.com](https://hdthomas.com/apps/interactful)
- **WWDC25 Session 280** — "Cook up a rich text experience in SwiftUI with AttributedString." [Video](https://developer.apple.com/videos/play/wwdc2025/280/)
- **Apple "Building rich SwiftUI text experiences"** — official guide. [Apple docs](https://developer.apple.com/documentation/swiftui/building-rich-swiftui-text-experiences)

---

#### Specs and conventions

- **CommonMark** — base Markdown spec. [Site](https://commonmark.org/)
- **GFM** — GitHub-flavored Markdown extensions (tables, strikethrough, task lists). [Spec](https://github.github.com/gfm/)
- **YAML 1.2** — frontmatter format. [Spec](https://yaml.org/spec/1.2.2/)
- **ULID** — sortable IDs (Pages, Collections, Spaces). [Spec](https://github.com/ulid/spec)
- **Notion data model** — reference for property types, database conventions. [Notion blog](https://www.notion.com/blog/data-model-behind-notion)

---

#### Maintenance notes

- This file is curated by hand. Add entries as research surfaces them; remove entries that become irrelevant after a library swap.
- For audit findings that affect specific libraries (version pins, compatibility caveats, license details), capture in the relevant entry above rather than in a separate document.
