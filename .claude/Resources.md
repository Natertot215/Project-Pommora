### Pommora — Resources

Catalogue of external resources (documentation, libraries, references) to consult during research and implementation. Items are listed for reference; not all are committed dependencies. Stack-conditional sections are marked.

---

#### Editor primitives

##### Direction (if React + Electron)

- **BlockNote** — open-source MPL-2.0 core. [Docs](https://www.blocknotejs.org/docs) · [Custom blocks guide](https://www.blocknotejs.org/docs/features/custom-schemas/custom-blocks) · [Slash menu](https://www.blocknotejs.org/docs/slash-menu) · [Theming](https://www.blocknotejs.org/docs/react/styling-theming/themes) · [Pricing / licensing](https://www.blocknotejs.org/pricing) · [GitHub](https://github.com/TypeCellOS/BlockNote)

  - **License note:** core is MPL-2.0 (open source, OSI-approved); the "XL" packages (`xl-multi-column`, `xl-pdf-exporter`, `xl-docx-exporter`, AI commands) are GPL-3.0 OR a paid commercial license ($195/mo). Pommora's project license determines whether `xl-multi-column` can be used directly or must be built custom in BlockNote core.

##### Pivot doors (kept open, not committed)

- **Tiptap** — MIT core editor + MIT `@tiptap/markdown` extension. Note: Tiptap eliminated their free Cloud/Pro plan in 2026; AI / Conversion / Collaboration / Comments features are paid. Free for Pommora's specific needs but commercial trajectory worth tracking. [Docs](https://tiptap.dev/docs/editor) · [Markdown extension](https://tiptap.dev/docs/editor/markdown) · [Pricing](https://tiptap.dev/pricing) · [GitHub](https://github.com/ueberdosis/tiptap)

- **Milkdown** — MIT, ProseMirror foundation, markdown-first by design (round-trip enforced at the framework level). [Docs](https://milkdown.dev/) · [Styling guide](https://milkdown.dev/docs/guide/styling) · [Crepe API](https://milkdown.dev/docs/api/crepe) · [Plugin awesome list](https://github.com/Milkdown/awesome) · [GitHub](https://github.com/Milkdown/milkdown)

- **Yoopta-Editor** — MIT, Slate-based, 20+ built-in plugins including a callout. [Site](https://yoopta.dev/) · [Docs](https://docs.yoopta.dev/) · [Callout plugin](https://github.com/yoopta-editor/Yoopta-Editor/blob/master/packages/plugins/callout/README.md) · [GitHub](https://github.com/yoopta-editor/Yoopta-Editor)

- **CodeMirror 6** — buffer-based editor (markdown literally *is* the document; round-trip is perfect by definition). Used as Obsidian Live Preview's foundation: `StateField` parses markdown, `Decoration.replace` swaps source ranges with `WidgetType` block widgets. Achieving prose-first feel (placeholder rendering, widget enter/exit, caret behavior across widget boundaries) is meaningfully more work than a block editor. Strongest "files canonical" guarantee in the React shortlist. [Docs](https://codemirror.net/) · [GitHub](https://github.com/codemirror/dev)

##### Editor research notes

- **BlockNote markdown is lossy by design.** Confirmed in official docs: nested non-list blocks get flattened on export, custom blocks need custom serializers, inline marks beyond built-ins drop silently. Custom serialization is achievable without forking ([Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426) — register `toExternalHTML`/markdown handlers per block spec) but covering every block type *is* the canonical-format guarantee, not a minor layer.

- **Milkdown / Yoopta** also use ProseMirror state / Slate JSON as the canonical store with markdown as an export. Same compromise as BlockNote — none of the React block editors are markdown-canonical out of the box; the "files canonical" guarantee is something you build on top of any of them.

---

#### React + Electron stack (one of two viable paths)

##### Shell, build, distribution

- **Electron** — desktop shell. [Docs](https://www.electronjs.org/docs/latest)

- **electron-vite** — Vite-first dev experience with HMR for the main process. Pairs with electron-builder for packaging; cleanest dev loop of the React tooling options. [Docs](https://electron-vite.org/)

- **Electron Forge 7+** — alternative all-in-one tool, official + maintained by the Electron team; first-party features (ASAR integrity, universal builds, code signing, notarytool) land here first. [Docs](https://www.electronforge.io/)

- **electron-builder** — packaging + bundled `electron-updater` for auto-update. [Docs](https://www.electron.build/) · [Auto-update](https://www.electron.build/auto-update.html)

- **@electron/rebuild** — native module rebuild for ABI compatibility (better-sqlite3). [GitHub](https://github.com/electron/rebuild)

- **@electron/notarize** — wraps Apple's `notarytool` (post-altool deprecation). [GitHub](https://github.com/electron/notarize)

- **Sentry-Electron** — crash reporting (Crashpad-backed; covers main/renderer/utility processes). [Docs](https://docs.sentry.io/platforms/javascript/guides/electron/)
- **Vite** — bundler / dev server. [Docs](https://vitejs.dev/)

##### UI, styling, components

- **React** — UI framework. [Docs](https://react.dev/)
- **TypeScript** — strict mode. [Docs](https://www.typescriptlang.org/docs/)

- **Tailwind CSS v4** — styling, with CSS custom properties from the design system. [Docs](https://tailwindcss.com/docs)

- **Storybook** — localhost component gallery. [Docs](https://storybook.js.org/docs)

- **Figma Code Connect** — link Figma components to real component code. [Docs](https://www.figma.com/code-connect-docs/)

- **react-material-symbols** — icon delivery. [npm](https://www.npmjs.com/package/react-material-symbols)

##### State, data, search

- **better-sqlite3** — SQLite for Node.js (WAL mode). [GitHub](https://github.com/WiseLibs/better-sqlite3)

- **SQLite FTS5** — full-text search. External-content mode + `unicode61` tokenizer (with `remove_diacritics=2`) is the recommended pattern for vault-scale (1k–10k pages). [SQLite docs](https://www.sqlite.org/fts5.html)

- **Zustand v5+** — state management; `zustand/vanilla` produces a framework-agnostic store that React binds via `useSyncExternalStore`. Conceptually translatable to `@Observable` + `ValueObservation` on a future Swift rebuild. Cleaner fit than Jotai / Valtio / Redux Toolkit / Preact Signals for solo work. [Docs](https://github.com/pmndrs/zustand)

- **TanStack Query v5** — alternative to a hand-rolled pub/sub for SQLite reactivity (manual `invalidateQueries` after every mutation). Heavier-weight pattern; the hand-rolled table-keyed pub/sub (~80 LOC, ports straight to Swift) is the lighter and more portable option. [Docs](https://tanstack.com/query/latest)

- **chokidar** — file watcher. [GitHub](https://github.com/paulmillr/chokidar) (audit recommended evaluating `@parcel/watcher` as a faster alternative — pending review)

- **@parcel/watcher v2.5+** — native FSEvents on macOS; used by VSCode/Nx/Tailwind; ms vs seconds on large trees compared to chokidar. Gotchas: editor atomic-save (write `.tmp` + rename) emits create+delete for the temp; debounce 50–100ms by path. APFS clones don't fire events. [npm](https://www.npmjs.com/package/@parcel/watcher)

- **gray-matter** — YAML frontmatter parser. [GitHub](https://github.com/jonschlinkert/gray-matter) (upstream stale since 2019; audit recommended `@11ty/gray-matter` fork or `remark-frontmatter` — pending review)

##### Markdown / parsing

- **remark + remark-directive + mdast-util-directive** — Markdown parser + container directive support for `:::columns`, `:::callout`. `directiveToMarkdown()` round-trips back to `:::` syntax. Nesting requires the outer fence to use more colons (`::::columns` containing `:::callout`) to avoid ambiguous closes. [remark](https://github.com/remarkjs/remark) · [remark-directive](https://github.com/remarkjs/remark-directive) · [mdast-util-directive](https://github.com/syntax-tree/mdast-util-directive)

- **@flowershow/remark-wiki-link v3.3.1+** — Obsidian-flavored wikilink parser; handles `[[name]]`, `[[name|alias]]`, `[[name#heading]]`, combined `[[name#heading|alias]]`, and `![[asset]]` embeds. Healthiest of the maintained options (alternatives `@portaljs/remark-wiki-link` ~2yr stale; `heavycircle/remark-obsidian` solo-maintained). [GitHub](https://github.com/flowershow/remark-wiki-link)

##### Drag-and-drop (Spaces)

- **dnd-kit** — drag-and-drop for the Spaces composer. Two confusingly-named packages: [@dnd-kit/core](https://github.com/clauderic/dnd-kit) (v6.x, stable) and [@dnd-kit/react](https://dndkit.com/react/) (v0.x, ground-up rewrite, pre-1.0).

---

#### SwiftUI stack (one of two viable paths)

Detailed in `// SwiftInfo.md`. Library shortlist:

##### Editor + parsing

- **Apple swift-markdown** — Markdown parser + AST. Block directives use DocC `@Name(args){}` syntax (NOT Pandoc `:::`). [GitHub](https://github.com/swiftlang/swift-markdown)
- **STTextView** — TextKit 2 NSTextView replacement with a SwiftUI shim (`STTextViewSwiftUI`). Drop down when SwiftUI's `TextEditor` can't deliver: line-number gutters, programmatic decoration insertion, multi-cursor, custom selection rendering. [GitHub](https://github.com/krzyzanowskim/STTextView)

##### Spaces (drag-and-drop blocks)

- **stevengharris/SplitView** — nestable resizable splits with persistence. [GitHub](https://github.com/stevengharris/SplitView)

- **visfitness/reorderable** — pure SwiftUI `ReorderableVStack` / `HStack`. [GitHub](https://github.com/visfitness/reorderable)

- **SwiftUIX** — large SwiftUI gap-filler (text views, scroll behavior, AppKit bridges). [GitHub](https://github.com/SwiftUIX/SwiftUIX)

##### State, data, file watching

- **GRDB.swift v7.5+** — SQLite for Swift; FTS5 first-class via `FTS5Pattern`; `ValueObservation.tracking { db in ... }` is the reactive primitive — `.values(in:)` returns an `AsyncThrowingStream` (Swift 6 idiom over Combine). Requires Swift 6.1+/Xcode 16.3+. [GitHub](https://github.com/groue/GRDB.swift)

- **@Observable macro** (Swift 5.9+, mature in 6.2) — non-negotiable for new SwiftUI code; per-property tracking eliminates wasteful redraws; `@State` replaces `@StateObject`. [Apple docs](https://developer.apple.com/documentation/observation)

- **SwiftData** — wraps Core Data; can't use a custom SQLite schema or FTS5 directly. Still not safe for Pommora's "files canonical + custom schema" shape in 2026. **Skip in favor of GRDB.**

- **EonilFSEvents** (or hand-rolled `FSEventStreamCreate`) — vault folder watching. `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool. Same APFS / atomic-rename gotchas as the React side. [EonilFSEvents on GitHub](https://github.com/eonil/FSEvents)

- **TestFlight for Mac** — fully shipped (post-2021); same capabilities as iOS, internal/external tester model, builds expire after 90 days. [Apple Developer](https://developer.apple.com/testflight/)

##### Mac OS integration (first-party APIs)

These are areas where SwiftUI has materially less friction than Electron — see `// SwiftInfo.md` for the gap analysis.

- **CoreSpotlight** — `CSSearchableItem` + `CSSearchableItemAttributeSet`; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links results back into the app. 
[Apple docs](https://developer.apple.com/documentation/corespotlight)

- **QuickLook Preview Extension** — ship a `QLPreviewProvider` subclass; 
declare `QLSupportedContentTypes` for `net.daringfireball.markdown`. Renders Pommora pages straight from Finder via spacebar. [Apple docs](https://developer.apple.com/documentation/quicklook)

- **NSServices** — declare in `Info.plist`, implement selector; e.g. "New Pommora Page from Selection". [Edenwaith guide](https://www.edenwaith.com/blog/index.php?p=133)

- **Share Extension** — receive shares from Safari/Mail/etc. into Pommora. Add a Share Extension target conforming to `NSExtensionPrincipalClass`. [Apple docs](https://developer.apple.com/documentation/foundation/nsextensionrequesthandling)

- **MenuBarExtra** (macOS 13+) — first-party menu-bar item; `.menuBarExtraStyle(.window)` enables rich popovers. [Apple docs](https://developer.apple.com/documentation/swiftui/menubarextra)

- **NSVisualEffectView via SwiftUI `Material`** — sidebar vibrancy / system materials. [Apple docs](https://developer.apple.com/documentation/swiftui/material)

- **Transferable + `.draggable` / `.dropDestination`** — Finder file-promise drag-out and drag-in (the area where Electron's story has been broken for years). [Apple docs](https://developer.apple.com/documentation/coretransferable/transferable)

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

- This file is curated by hand. Add entries as research surfaces them; remove entries that become irrelevant after a stack pivot or library swap.
- For audit findings that affect specific libraries (version pins, compatibility caveats, license details), capture in the relevant entry above rather than in a separate document.
- When the stack lands and the React vs SwiftUI section is no longer dual, prune the unused half.
