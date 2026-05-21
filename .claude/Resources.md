### Pommora — Resources

External resources (docs, libraries, references) for research and implementation. Listed for reference; not all are committed dependencies.

---

#### Editor + parsing (shipped Swift path)

Editor shipped at v0.2.7.0 on native TextKit 2. Swift-side primitives:

- **Apple swift-markdown** (0.8.0) — full GFM AST. SPM dep on `swiftlang/swift-markdown`. Block directives use DocC `@Name(args){}` syntax (NOT Pandoc `:::`). [GitHub](https://github.com/swiftlang/swift-markdown)
- **`swift-markdown-engine`** — vendored locally at `External/MarkdownEngine/` (upstream `nodes-app/swift-markdown-engine`, Apache 2.0). Provides the dynamic-syntax + Markdown-aware typing layer Apple's bare NSTextView lacks. Pommora owns the vendored copy; modification log lives at `External/MarkdownEngine/NOTICE.md`.
- **`AppleASTSupplementalStyler`** — Pommora-side styler in the vendored engine; layers BlockQuote / Strikethrough / Table / ThematicBreak on top of the engine's regex tokenizer.
- **STTextView** — TextKit 2 NSTextView replacement (Krzyzanowski). Not adopted in v0.2.7.0; useful reference for line-number gutters / programmatic decoration insertion / multi-cursor. [GitHub](https://github.com/krzyzanowskim/STTextView)
- **[Shpigford/clearly](https://github.com/Shpigford/clearly)** — native AppKit / SwiftUI markdown editor for macOS. Source-with-decorations editor with syntax highlighter + fold plumbing. Kept as a fork-reference for the native swift-markdown path. License: FSL-1.1-MIT (converts to MIT Feb 2028).
- **[Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor)** — Swift Package wrapping CodeMirror 6 in WKWebView. **Tried + abandoned** during v0.2.7 prep (didn't deliver the macOS-native feel); see `// Features//PageEditor.md` for the pivot story. Listed here as a historical anchor only.

#### React-contingency editor candidates

Reference material for a hypothetical React+Electron pivot — NOT active dependencies. Full React-side architecture → `// ReactInfo// Editor.md` and `// ReactInfo// Resources.md`.

- **BlockNote** — open-source MPL-2.0 core; block editor built on Tiptap. Slash menu, formatting toolbar, drag handles wired by default. [Docs](https://www.blocknotejs.org/docs) · [GitHub](https://github.com/TypeCellOS/BlockNote). License note: the "XL" packages (`xl-multi-column`, exporters, AI commands) are GPL-3.0 OR a paid commercial Business subscription.
- **Tiptap** — MIT-licensed headless ProseMirror-React framework. Every package Pommora would use ships under MIT. [Docs](https://tiptap.dev/docs/editor) · [GitHub](https://github.com/ueberdosis/tiptap)
- **Milkdown** — MIT, ProseMirror foundation, markdown-first by design (round-trip enforced at framework level). [Docs](https://milkdown.dev/) · [GitHub](https://github.com/Milkdown/milkdown)
- **Yoopta-Editor** — MIT, Slate-based, 20+ built-in plugins including a callout. [Site](https://yoopta.dev/) · [GitHub](https://github.com/yoopta-editor/Yoopta-Editor)
- **CodeMirror 6** — buffer-based editor (markdown literally *is* the document). Used as Obsidian Live Preview's foundation. [Docs](https://codemirror.net/) · [GitHub](https://github.com/codemirror/dev)

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

Areas where SwiftUI is first-party and Electron has ceilings or companion-bundle workarounds.

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

- Curated by hand. Add as research surfaces; remove after library swaps.
- Library-specific audit findings (version pins, compatibility, license) capture in the relevant entry above, not in a separate doc.
