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

#### On-device AI and language intelligence

A capability cluster — every entry below is on-device (no network egress, no API keys, sandbox-friendly). Maps directly to the **AI chat in inspector** Prospect, future semantic backlinks, and smart property extraction.

- **Apple Foundation Models framework** (macOS 26+ / iOS 26+) — first-party access to the on-device Apple Intelligence model. Streaming text, tool calling, structured generation, embeddings. Free, sandbox-safe, no entitlement. The natural primary path for any Pommora-side AI (summarize Page, suggest tags, "what is this Page about" panel, semantic-search query rewriting). Limited to Apple Silicon Macs and Apple Intelligence-eligible iPhones/iPads. [Apple docs](https://developer.apple.com/documentation/foundationmodels) · [WWDC25 Session 286](https://developer.apple.com/videos/play/wwdc2025/286/)

- **MLX + mlx-swift / mlx-swift-examples** — Apple's array framework for Apple Silicon, with first-party Swift bindings. Runs Llama-, Mistral-, Phi-, Qwen-class models locally on M-series GPUs. The fallback when Foundation Models isn't enough (longer context windows, custom fine-tunes, models that predate Apple Intelligence). Apache-2.0. [mlx-swift](https://github.com/ml-explore/mlx-swift) · [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)

- **llama.cpp + LLMFarm / SwiftLlama bindings** — GGUF runner; broader model zoo than MLX but slower on Apple Silicon than MLX-native ports. Useful only if a specific community model lives in GGUF and not MLX. MIT (llama.cpp). [llama.cpp](https://github.com/ggerganov/llama.cpp) · [SwiftLlama](https://github.com/ShenghaiWang/SwiftLlama)

- **NaturalLanguage framework** — `NLTagger` for named-entity recognition, `NLEmbedding` for word/sentence vectors (no model download — built into the OS). Cheap path to "this Page mentions these people / places / orgs" backlink suggestions and a baseline semantic-search index before bringing in heavier embeddings. First-party, free. [Apple docs](https://developer.apple.com/documentation/naturallanguage)

- **Speech framework + `SFSpeechRecognizer`** — on-device dictation into the editor. Unlocks "dictate a Page" without leaving the app. Free, requires mic entitlement. [Apple docs](https://developer.apple.com/documentation/speech)

- **AVSpeechSynthesizer** — read-aloud for any Page. Useful accessibility surface and a "listen to my notes" mode. Free, first-party. [Apple docs](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)

#### Capture and ingestion

System-side affordances for getting content *into* Pommora from elsewhere — bidirectional to the existing Share Extension / Transferable entries above.

- **VisionKit `DataScannerViewController` + Continuity Camera** — point an iPhone at a whiteboard, the image streams into the Mac and OCR'd text lands as a Pommora Page. Live Text built-in. Pairs with the iPad/iOS Prospect; on Mac alone, Continuity Camera + `VNRecognizeTextRequest` covers the same ground. [VisionKit docs](https://developer.apple.com/documentation/visionkit) · [Continuity Camera](https://support.apple.com/HT213244)

- **Vision `VNRecognizeTextRequest`** — OCR for any image dropped onto a Page. Turn screenshots into searchable, paste-able text; index image attachments in the SQLite FTS5 layer alongside Markdown bodies. First-party, free, fast. [Apple docs](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)

- **LinkPresentation framework** — `LPMetadataProvider` fetches title / favicon / hero image for a URL and renders an `LPLinkView`. Drop-in path for Notion-style rich link previews when a wikilink or external URL is hovered / pinned. First-party, free, async-friendly. [Apple docs](https://developer.apple.com/documentation/linkpresentation)

- **PDFKit `PDFDocument`** — extract text, render thumbnails, view inline. Unlocks a PDF attachment block inside Spaces (and PDF-as-source for an AI summarization flow). First-party, free. [Apple docs](https://developer.apple.com/documentation/pdfkit)

- **SwiftSoup** — HTML → DOM → Markdown converter primitive. Backs a "paste rich text from browser → clean Markdown" path that goes well beyond what the OS clipboard offers. MIT. [GitHub](https://github.com/scinfu/SwiftSoup)

- **Yams** — YAML 1.2 reader/writer in pure Swift. The default choice for Page frontmatter (which is YAML). MIT, no native deps. [GitHub](https://github.com/jpsim/Yams)

#### System invocation and automation

Pommora-as-target: let macOS itself drive the app from outside its window.

- **App Intents framework** — declarative actions registered with the system. Each `AppIntent` becomes a Shortcuts step, a Spotlight result, an Apple Intelligence tool call, and a Siri action — same code path. The right place for "Create Page from selection," "Open Pommora Page <name>," "Add to Items collection <name>." First-party, macOS 13+. Pommora-native pairing with Foundation Models is meaningful here — your own AppIntents become tools Apple Intelligence can invoke. [Apple docs](https://developer.apple.com/documentation/appintents) · [WWDC22 Session 10032](https://developer.apple.com/videos/play/wwdc2022/10032/)

- **NSUserActivity** — register the open Page as a continuable activity so Handoff lets a user pick up on iPad mid-edit, and the system can resurface it in Spotlight / Stage Manager. Also the substrate for `CSSearchableItemActionType` deep-link results (already in the CoreSpotlight entry). First-party. [Apple docs](https://developer.apple.com/documentation/foundation/nsuseractivity)

- **AppleScript / JXA support** — declare a scripting dictionary (`.sdef`) and Pommora becomes scriptable from Script Editor, Hammerspoon, Keyboard Maestro, Alfred workflows. Cheap power-user surface that Notion / Obsidian both lack on Mac. [Apple docs](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptX/AppleScriptX.html)

- **Focus Filters API** (`SetFocusFilterIntent`) — let macOS Focus modes scope Pommora to a specific nexus or Collection (e.g., "Work focus shows only the Work nexus"). First-party, low effort, very Apple-flavored. [Apple docs](https://developer.apple.com/documentation/appintents/setfocusfilterintent)

#### Multi-device sync substrate

For the **Cloud sync** and **Mobile companion** Prospects. None of these are committed; this is the menu when sync becomes a phase.

- **CloudKit + `CKSyncEngine`** — Apple's managed sync. `CKSyncEngine` (introduced 2023, mature by 2025) is the modern replacement for the older subscription/zone juggling; it handles conflict-free queueing and reachability for you. Free for users (their iCloud quota), zero infra to operate, identity is the iCloud account. Strongest cohesion fit; weakest portability (Apple-only). [Apple docs](https://developer.apple.com/documentation/cloudkit/cksyncengine) · [WWDC23 Session 10188](https://developer.apple.com/videos/play/wwdc2023/10188/)

- **iCloud Drive ubiquity container** — point the nexus at `~/Library/Mobile Documents/iCloud~com~pommora~nexus/Documents`; iCloud transparently syncs `.md` / `.json` files across the user's Apple devices. Lowest-effort cross-device sync. Conflict resolution is per-file last-write-wins (not great for concurrent edits — fine for personal-first single-user). Falls out of Pommora's "files are canonical" stance for free. [Apple docs](https://developer.apple.com/icloud/cloudkit/)

- **Y-Swift / Yniffy** — Swift bindings for Yjs (the CRDT library Notion-style collaborative editors use). Per-document CRDT state; integrates cleanly with Tiptap / BlockNote (which already speak Yjs natively) under the Option 2 editor path. MIT. The route to true concurrent multi-device editing without conflicts. [Y-Swift](https://github.com/heckj/y-swift)

- **Automerge-Swift** — alternative CRDT with a JSON-native data model (better fit for `_collection.json` schemas and Items than for prose). Automerge 2 has a Swift package with a Rust core. MIT. [GitHub](https://github.com/automerge/automerge-swift)

- **Loro** — newer high-perf CRDT (Rust core, Swift bindings via FFI). Smaller, faster, less battle-tested than Yjs/Automerge. MIT. [Site](https://loro.dev/) · [GitHub](https://github.com/loro-dev/loro)

- **Supabase Swift SDK** — if Pommora's cloud goes the way `Prospects.md` hints (Postgres-backed, parallel to local SQLite). Auth, realtime, storage, edge functions. MIT. [GitHub](https://github.com/supabase/supabase-swift)

#### Spaces — rich block types

Block types that go beyond text / image / linked-pages — fuel for the v0.10–v0.11 Spaces work and post-v1 Space blocks.

- **Swift Charts** — first-party charting (macOS 13+). Foundation for a future "chart from a Collection" block in Spaces (e.g., group Tasks Collection by status, render as bar chart). Declarative SwiftUI API, near-zero ceremony. [Apple docs](https://developer.apple.com/documentation/charts)

- **AVKit `VideoPlayer`** — SwiftUI video block in Spaces. Drop a `.mp4` into a Space, get a system-quality player. First-party. [Apple docs](https://developer.apple.com/documentation/avkit/videoplayer)

- **PencilKit** — iPad-only sketch block (gates on the Mobile Companion Prospect). Drawings persist as `.drawing` data or as PNG snapshots inside Spaces. First-party. [Apple docs](https://developer.apple.com/documentation/pencilkit)

- **Mermaid.js** — text-defined diagrams (flowcharts, sequence, gantt). Renders inside the Option 2 WKWebView trivially; would need a JS bridge for Option 1. The de-facto diagram syntax for Markdown ecosystems — Obsidian and Notion both ship it. MIT. [Site](https://mermaid.js.org/)

- **KaTeX** (or MathJax) — math equation rendering. KaTeX is the faster, simpler one; same WKWebView bridge story as Mermaid. MIT. [Site](https://katex.org/)

- **Lottie (lottie-ios)** — render After Effects animations as a Space block. Niche but a high-delight surface for "cover art" on a Space. Apache-2.0. [GitHub](https://github.com/airbnb/lottie-ios)

- **Pow** — SwiftUI animation/transition library (the Movin maintainer's open-source effects pack). Sweetens the editor and Spaces canvas without writing custom animations. MIT. [GitHub](https://github.com/EmergeTools/Pow)

#### Code blocks — syntax highlighting

For v0.3 code blocks. Both editor paths need a highlighter; the choice depends on Option 1 vs 2.

- **Splash** — pure-Swift Swift-only syntax highlighter by John Sundell. Tiny, fast, MIT. The right answer if Pommora wants gorgeous Swift highlighting and "good enough" for other languages via fallback. Option 1 friendly. [GitHub](https://github.com/JohnSundell/Splash)

- **Highlightr** — Swift wrapper around highlight.js running in a hidden `JSContext`. ~190 languages out of the box, theme switching, AttributedString output. MIT. The pragmatic Option 1 answer. [GitHub](https://github.com/raspu/Highlightr)

- **Sourceful** — TextKit-based source editor view with built-in highlighting. Useful if a Page-side code block ever needs to be editable in-place with the same highlighting as the rendered view. MIT. [GitHub](https://github.com/twostraws/Sourceful)

- **tree-sitter + tree-sitter-swift** — incremental parser the new generation of editors (Zed, Neovim, Helix) standardize on. Overkill for v0.3 code blocks; the right answer if Pommora ever ships a real in-app code editor surface. MIT. [tree-sitter](https://tree-sitter.github.io/) · [Swift bindings](https://github.com/ChimeHQ/SwiftTreeSitter)

- **Option 2 inheritance:** if the editor path is WKWebView, BlockNote / Tiptap / Milkdown / CodeMirror all ship code-block highlighting wired to Shiki or highlight.js — zero additional Swift work. The entries above only matter for Option 1.

#### Plugin and scripting surface

For the long-tail "plugin system" Prospect and any in-app user scripting.

- **JavaScriptCore.framework** — first-party JS engine. Run untrusted plugin JS in a sandboxed `JSContext`, expose Pommora APIs as `JSExport` protocols. The path Obsidian's plugin system takes (modulo Electron). Free, mature. [Apple docs](https://developer.apple.com/documentation/javascriptcore)

- **WasmKit** — pure-Swift Wasm runtime. Sandboxed, language-agnostic plugins (Rust / Go / Zig / AssemblyScript → `.wasm`). Younger than JavaScriptCore but the cleaner architectural answer for plugin isolation. Apache-2.0. [GitHub](https://github.com/swiftwasm/WasmKit)

- **swift-syntax** — Apple's Swift parser. Only relevant if "user-authored Pommora plugins in Swift" becomes the model — would compile-and-load via `swift-package-manager` at runtime. Niche. Apache-2.0. [GitHub](https://github.com/swiftlang/swift-syntax)

#### Mac quality-of-life utilities

The Sindre Sorhus stack — every Mac indie app uses some subset of these because each one replaces 50–200 lines of glue with one import.

- **KeyboardShortcuts** — user-customizable global hotkeys with a built-in recorder view. Backed by Carbon hotkey APIs, sandbox-safe. Drop-in for a "quick capture from anywhere" hotkey. MIT. [GitHub](https://github.com/sindresorhus/KeyboardShortcuts)

- **Defaults** — type-safe `UserDefaults` wrapper with `@Default` property wrappers and Combine/`AsyncSequence` change streams. The default choice over hand-rolled UserDefaults plumbing. MIT. [GitHub](https://github.com/sindresorhus/Defaults)

- **Settings** (formerly Preferences) — Mac-native settings window with tabs, sidebars, search. Skip rebuilding the Settings UI for v0.12 in-app customization. MIT. [GitHub](https://github.com/sindresorhus/Settings)

- **LaunchAtLogin-Modern** — sandbox-compatible "open at login" toggle. MIT. [GitHub](https://github.com/sindresorhus/LaunchAtLogin-Modern)

- **Sparkle 2.x** — non-MAS auto-update standard, already noted in `PommoraPRD.md`. EdDSA-signed, SwiftUI integration via `SPUStandardUpdaterController`. MIT-ish (Sparkle license). [GitHub](https://github.com/sparkle-project/Sparkle)

- **CryptoKit** — first-party AES-GCM / HKDF / Curve25519. Required as soon as Pommora needs an encrypted property type or a "lock this Page" feature. Free, no entitlement. [Apple docs](https://developer.apple.com/documentation/cryptokit)

- **Security framework (Keychain)** — store nexus passphrases, sync tokens, AI provider keys (if ever applicable). First-party. [Apple docs](https://developer.apple.com/documentation/security/keychain_services)

#### Swift ecosystem standard libs

Apple-maintained Swift packages used so universally they're effectively part of the language.

- **swift-collections** — `OrderedDictionary`, `OrderedSet`, `Deque`, `BitArray`, `Heap`, `TreeSet`. `OrderedDictionary` is the right backing type for the tab strip; `OrderedSet` is the right backing type for "selected sidebar items"; `Deque` for any LRU-style recent-Pages cache. Apache-2.0. [GitHub](https://github.com/apple/swift-collections)

- **swift-algorithms** — `chunks(ofCount:)`, `windows(ofCount:)`, `uniqued()`, `interspersed(with:)`, `product()`, etc. Sharpens nexus-scan and view-rendering code dramatically. Apache-2.0. [GitHub](https://github.com/apple/swift-algorithms)

- **swift-async-algorithms** — `debounce`, `throttle`, `merge`, `chain` on `AsyncSequence`. The right primitive for FSEvents → SQLite debouncing (alternative to hand-rolling timers). Apache-2.0. [GitHub](https://github.com/apple/swift-async-algorithms)

- **swift-testing** — Apple's modern testing framework (Swift Testing, not XCTest). Trait-based, parameterized, expression-level assertions, parallel by default. Should be the default for new Pommora tests on Xcode 16+. Apache-2.0. [GitHub](https://github.com/swiftlang/swift-testing)

- **swift-log + swift-metrics** — Apple-blessed structured logging / metrics façades. Pair with `OSLog` / `MetricKit` on Apple platforms; portable elsewhere. Apache-2.0. [swift-log](https://github.com/apple/swift-log) · [swift-metrics](https://github.com/apple/swift-metrics)

#### Apple platform reach — iPad, iOS, beyond

For the Mobile Companion Prospect. Mostly free with the SwiftUI stack — listed here so the surface is named.

- **TipKit** (iOS 17+ / macOS 14+) — first-party in-app tip system; declarative, scoped to feature activation events. The right way to onboard users into Pommora's Collection kinds and Spaces affordances without writing a tour. [Apple docs](https://developer.apple.com/documentation/tipkit)

- **WidgetKit** — desktop / Lock Screen / Notification Center widgets. A "Today's Pages" or "Quick Capture" widget is a single SwiftUI view + a `TimelineProvider`. First-party. [Apple docs](https://developer.apple.com/documentation/widgetkit)

- **App Intents Spotlight donations** — every `AppIntent` Pommora ships automatically appears as a Spotlight result; donate `IntentDonation` to surface relevant actions contextually. Pairs with the App Intents entry above. [Apple docs](https://developer.apple.com/documentation/appintents/donating-shortcuts)

- **Live Activities + ActivityKit** (iOS 16+) — Lock Screen / Dynamic Island surfaces. Niche for Pommora; could surface "Active timer block in Page X" or sync progress. iOS-only. [Apple docs](https://developer.apple.com/documentation/activitykit)

- **Multipeer Connectivity** — peer-to-peer transport over Bluetooth + WiFi. A LAN-only "share nexus to nearby iPad" path that needs no cloud. First-party, free, niche. [Apple docs](https://developer.apple.com/documentation/multipeerconnectivity)

#### Performance and quality

Lightweight observability — important now that v0.2 is wiring up an index + watcher.

- **OSLog + `Logger` + signposts** — first-party structured logging that streams to Console.app and Instruments. `os_signpost` ranges around FSEvents debounce, SQLite migrations, editor parse are free perf telemetry. Replaces `print` everywhere. [Apple docs](https://developer.apple.com/documentation/os/logging)

- **MetricKit** — first-party crash, hang, energy, and disk-IO reports automatically delivered by the OS (opt-in by user). Zero-cost regression detection across real users post-release. [Apple docs](https://developer.apple.com/documentation/metrickit)

- **Instruments + `.trace` files** — the SwiftUI expert skill already covers this; calling it out as the SwiftUI hitch / hang / view-update debugging surface. [Apple docs](https://help.apple.com/instruments/mac/current/)

- **ViewInspector** — runtime SwiftUI introspection for tests; lets unit tests query rendered view trees without snapshot fragility. MIT. [GitHub](https://github.com/nalexn/ViewInspector)

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
