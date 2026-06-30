### Pommora — Resources

External resources (docs, libraries, references) for research and implementation. Listed for reference; not all are committed dependencies.

---

#### Editor + parsing (shipped Swift path)

Editor shipped at v0.2.7.0 on native TextKit 2. Swift-side primitives:

- **Apple swift-markdown** (0.8.0) — full GFM AST. SPM dep on `swiftlang/swift-markdown`. Block directives use DocC `@Name(args){}` syntax (NOT Pandoc `:::`). [GitHub](https://github.com/swiftlang/swift-markdown)
- **`MarkdownPM`** — Pommora-owned Swift Package at `External/MarkdownPM/` (originally vendored from `nodes-app/swift-markdown-engine`, Apache 2.0; now owned + maintained in-tree). Provides the dynamic-syntax + Markdown-aware typing layer Apple's bare NSTextView lacks. Front-door type is `MarkdownPMEditor`; modification log lives at `External/MarkdownPM/NOTICE.md`.
- **`AppleASTSupplementalStyler`** — Pommora-side helper composed LAST after the owned `MarkdownPMStyler`'s primary pass (last-writer-wins); layers BlockQuote / Strikethrough / Table / ThematicBreak on top.
- **[Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor)** — Swift Package wrapping CodeMirror 6 in WKWebView. **Tried + abandoned** during v0.2.7 prep (didn't deliver the macOS-native feel); see `// Features//PageEditor.md` for the pivot story. Listed here as a historical anchor only.

#### Spaces (drag-and-drop blocks)

- **stevengharris/SplitView** — nestable resizable splits with persistence. [GitHub](https://github.com/stevengharris/SplitView)

- **visfitness/reorderable** — pure SwiftUI `ReorderableVStack` / `HStack`. [GitHub](https://github.com/visfitness/reorderable)

- **SwiftUIX** — large SwiftUI gap-filler (text views, scroll behavior, AppKit bridges). [GitHub](https://github.com/SwiftUIX/SwiftUIX)

#### State, data, file watching

- **GRDB.swift** (6.29.3 pinned) — SQLite for Swift; FTS5 first-class via `FTS5Pattern`; `ValueObservation.tracking { db in ... }` is the reactive primitive — `.values(in:)` returns an `AsyncThrowingStream` (Swift 6 idiom over Combine). [GitHub](https://github.com/groue/GRDB.swift)

- **Nuke** (13.0.6 pinned) — image-loading pipeline (with NukeUI) powering page covers, container banners, and the gallery cards; resizes + disk-caches across launches. Drives `Detail/Gallery/`, `Detail/Covers/BannerView.swift`, and `Sidebar/NexusHeaderBanner.swift`. [GitHub](https://github.com/kean/Nuke)

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

- **MenuBarExtra** (macOS 13+) — first-party menu-bar utility; `.menuBarExtraStyle(.window)` enables rich popovers. [Apple docs](https://developer.apple.com/documentation/swiftui/menubarextra)

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
- **ULID** — sortable IDs (Pages, Collections, Areas). [Spec](https://github.com/ulid/spec)
- **Notion data model** — reference for property types, database conventions. [Notion blog](https://www.notion.com/blog/data-model-behind-notion)

---

#### Maintenance notes

- Curated by hand. Add as research surfaces; remove after library swaps.
- Library-specific audit findings (version pins, compatibility, license) capture in the relevant entry above, not in a separate doc.
