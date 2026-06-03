## MarkdownPM — Code Map & Dependency Report

This report merges 22 structured slice-maps of the vendored `MarkdownEngine` package (the v3 "MarkdownPM" rebuild target). All file:line citations are preserved from the slices and were verified against source by the slice authors; the graphify graph is build-artifact-level only and grounds no symbol-call edges. Paths are relative to `External/MarkdownEngine/Sources/MarkdownEngine/` unless otherwise rooted.

The six rebuild phases referenced throughout:
- **P1** — Re-home into the Pommora-owned MarkdownPM package + module rename.
- **P2** — Characterization test net (must land before P3+).
- **P3** — Single cached parse spine (the #9 fix).
- **P4** — Inline locating on the Apple swift-markdown AST + delete the hand-rolled emphasis parser.
- **P5** — One owned styler + theme.
- **P6** — Body-orchestration tidy + verbatim transplant of OS workarounds.

### Module Map

LOC values are taken from the slice that read each file in full; "—" means the file appeared only as a dependency/caller and its LOC was not measured.

| File (under `Sources/MarkdownEngine/` unless noted) | Role | LOC | Phases |
|---|---|---|---|
| `TextView/NativeTextViewWrapper.swift` | Public SwiftUI bridge (NSViewRepresentable); the sole public front door | 413 | 1,2,3,6 |
| `TextView/NativeTextViewSelectionTypes.swift` | Public selection/replacement value types (all app-dormant) | 89 | 1,2 |
| `TextView/Coordinator/NativeTextViewCoordinator.swift` | @MainActor NSTextViewDelegate; owns all stored state, the parse-cache fields, `ParsedDocument` struct, `@Binding text` save sink | 339 | 1,3,4,6 |
| `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift` | The parse cache spine (`parsedDocument(for:)`) + both styling entry paths + paragraph scoping + inline replacement | 316 | 1,2,3,4,5,6 |
| `TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift` | Hot keystroke path; per-edit re-tokenize/re-style + the body-text save (line 70) | 502 | 1,2,3,4,5,6 |
| `TextView/Coordinator/NativeTextViewCoordinator+Services.swift` | Find-highlight, bus, autocorrect/spell policy, code-block overlay, Writing-Tools recovery, inline-selection geometry | 517 | 1,2,3,4,6 |
| `TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift` | Foldable-headings service; sole writer of `foldedRanges`; elision delegate; chevron animation; a 2nd Apple parse | 558 | 1,2,3,4,6 |
| `TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift` | Sole writer of ThematicBreak/HR visual attributes; reentry-guarded caret-aware HR service | 278 | 1,2,3,4,5,6 |
| `TextView/ContextMenu.swift` | Bus-action handlers; 10 raw `self.text = tv.string` save sites; 2 `parsedDocument` callers | — | 6 |
| `TextView/NativeTextView/NativeTextView.swift` | NSTextView subclass; all view state, caret-KVO, `setMarkedText` restyle, appearance forwarding | 82 | 1,2,6 |
| `TextView/NativeTextView/NativeTextView+CaretWorkarounds.swift` | FB22524198 caret Y-snap + block-image caret policy (keep-verbatim) | 107 | 1,2,6 |
| `TextView/NativeTextView/NativeTextView+SpellingPolicy.swift` | `setSpellingState` suppression inside code/LaTeX/suppressed tokens | 39 | 1,3 |
| `TextView/NativeTextView/NativeTextView+TaskCheckbox.swift` | Checkbox hit-test + toggle; reads/writes `.taskCheckbox` | 57 | 1,2,5 |
| `TextView/NativeTextView/NativeTextView+PasteHandling.swift` | `paste(_:)` image/text/file-URL handling + sanitization | 92 | 1,2 |
| `TextView/NativeTextView/NativeTextView+ClickRemap.swift` | Click-in-paragraph-spacing caret remap (pure geometry) | 57 | 1,2 |
| `TextView/NativeTextView/NativeTextView+DragSelectBoost.swift` | `mouseDown` dispatch chain + drag-autoscroll boost | 66 | 1,2,6 |
| `TextView/NativeTextView/NativeTextView+FrameAndOverscroll.swift` | Frame sizing, TK2 height measurement, overscroll, scroll suppression | 144 | 1,2,6 |
| `TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift` | Tracking-area hover + chevron hit-test/click/fold (Pommora addition) | 284 | 1,2,4,6 |
| `Parser/MarkdownTokenizer.swift` | Regex/stack tokenizer (`parseTokens`); math/currency heuristic; heading regex #1 | 242 | 1,2,3,4,6 |
| `Parser/MarkdownTokenizer+Emphasis.swift` | Hand-rolled CommonMark asterisk emphasis parser (whole file) | 173 | 1,2,4 (DELETE) |
| `Parser/MarkdownToken.swift` | `MarkdownToken` struct + `MarkdownTokenKind` enum (internal); public `.wikiLinkID`/`.taskCheckbox` keys; 2 geometry helpers | 68 | 1,2,3,4,5 |
| `Parser/MarkdownPlainText.swift` | Public `extract(from:)` AST walker (word/char counts); app-only consumer | 48 | 1,2,4,6 |
| `Parser/MarkdownDetection.swift` | `isInside*` / `isThematicBreakLine` / `isDashBulletLine` / `isHeadingLine` (heading regex #2) / `foldableHeadings` / `reconcileFoldedHeadings` / `computeActiveTokenIndices`; `FoldedHeading` | 437 | 1,2,3,4,5,6 |
| `Styling/MarkdownStyler.swift` | Primary (regex-token) styler; `StylingContext`; `StyledRange` typealias; owns code/inline-code/checkbox/incomplete-bracket/shrink passes | 613 | 1,2,3,4,5,6 |
| `Styling/MarkdownStyler+TextStyling.swift` | `styleHeadings` + `styleEmphasis` (per-char trait merge) | 132 | 1,2,4,5 |
| `Styling/MarkdownStyler+Links.swift` | `styleAutoLinks`/`styleWikiLinks`/`styleMarkdownLinks`; only resolver caller (line 59) | — | 1,4,5 |
| `Styling/MarkdownStyler+Latex.swift` | `styleBlockLatex`/`styleInlineLatex` (kern-overlay) | — | 1,4,5,6 |
| `Styling/MarkdownStyler+Images.swift` | `styleImageEmbeds` (`![[Name]]`) | — | 1,4,5,6 |
| `Styling/AppleASTSupplementalStyler.swift` | Supplemental Apple-AST styler (BlockQuote/Strikethrough/Table/ThematicBreak-noop); hosts `SourceRangeConverter` + `LineOffsetIndex`; the always-on uncached parse | 379 | 1,2,3,4,5,6 |
| `Styling/TextStylingService.swift` | Per-edit restyle orchestrator; the primary+supplemental merge point (line 94) | 149 | 1,2,3,5,6 |
| `Styling/HeadingHelpers.swift` | Shared measurement helpers (`headingFontMultiplier`/`latexFontSize`/`textWidth`/`checkboxExtraSpacing`) | 54 | 1,4,5 |
| `Input/MarkdownInputHandler.swift` | Facade (`handleListInsertion`→`MarkdownLists`) + Pommora char-pair auto-pair/auto-delete + block-LaTeX/image auto-wrap | 275 | 1,2,3,6 |
| `Input/MarkdownListHandler.swift` | `struct MarkdownLists`: full keystroke cascade (the 9 transforms + Enter/Tab/blockquote/code-fence) + `performEdit` + mis-homed `paragraphAttributes` | 900 | 1,2,3,4,5,6 |
| `Renderer/MarkdownTextLayoutFragment.swift` | NSTextLayoutFragment subclass; per-fragment AST detection + all overlays + FB15131180 extra-line pin + `MarkdownLayoutManagerDelegate` | 1202 | 1,2,3,4,5,6 |
| `Renderer/LayoutBridge.swift` | `layoutBridgeDefaultLineHeight` + `removeTemporaryAttribute` + NSRange↔NSTextRange | — | 1 |
| `Configuration/MarkdownEditorTheme.swift` | 12 NSColor theme slots (8 system, 4 literals) | 116 | 1,2,5 |
| `Configuration/MarkdownEditorConfiguration.swift` | Top-level config (18 props) + 16 inline value sub-structs | 499 | 1,2,5,6 |
| `Services/MarkdownEditorServices.swift` | `WikiLinkResolver` protocol + `NoOpWikiLinkResolver` (only conformance) + services container | 255 | 1,5 |
| `Services/WikiLinkService.swift` | Live display↔storage transform; `RangeKey`/`LinkMetadata`; two regexes | 201 | 1,2,3,4,5,6 |
| `Util/HeadingChevronGeometry.swift` | Shared chevron rect math (draw + hover agree) | 39 | 1 |
| `Util/NSTextLayoutFragment+NSRange.swift` | `nsRange` computed property bridge | — | 1 |
| `Package.swift` | SPM manifest (name `MarkdownEngine`, swift-tools 5.9, swift-markdown exact 0.8.0) | 44 | 1 |
| `Tests/MarkdownEngineTests/EnterContinuationTests.swift` | Only engine-own test file (Enter + checkbox); NOT in Pommora scheme | 106 | 1,2 |
| `NOTICE.md` | Per-file vendoring/modification ledger | 46 | 1,5 |
| **App-side (under `Pommora/Pommora/`)** | | | |
| `Pages/PageEditorView.swift` | The ONLY editor call site (wrapper @210) + config (@351) | 499 | 1,5 |
| `Pages/PageEditorViewModel.swift` | Owns `body`/`foldedHeadings`; debounced save; `reconcileFoldedHeadings` @92 | 158 | 1,3,4,6 |
| `Pages/PageTextStats.swift` | `MarkdownPlainText.extract` consumer @36 | 49 | 1,3 |
| `Content/PageFrontmatter.swift` | On-disk `folded_headings:[String]?` @36 (Pages-only) | — | 2,4 |
| `Content/PageFile.swift` | `save` → `AtomicYAMLMarkdown.write(preservingFrom:modeledKeys:)` | 121 | 6 |
| `AtomicIO/AtomicYAMLMarkdown.swift` | `mergedData` frontmatter-preservation (foreign keys pass-through) | — | 6 |
| **App test files (under `Pommora/PommoraTests/`)** | | | |
| `Pages/FoldableHeadingsTests.swift` | `foldableHeadings`/`reconcileFoldedHeadings` characterization seed | 262 | 2,4 |
| `Pages/PageTextStatsTests.swift` | `MarkdownPlainText.extract` + `PageTextStats` | 62 | 2 |
| **Project wiring** | | | |
| `Pommora/Pommora.xcodeproj/project.pbxproj` | `XCLocalSwiftPackageReference` @611 + product dep @650 + links | — | 1 |
| `Pommora/Pommora.xcodeproj/xcshareddata/xcschemes/Pommora.xcscheme` | TestAction Testables = PommoraTests + PommoraUITests only | 103 | 2 |

### Dependency Graph (load-bearing edges)

#### A. The parse fan-out — `Document(parsing:)` + `parsedDocument(for:)`

There are **two disjoint parse systems**. The regex tokenizer (`MarkdownTokenizer.parseTokens`, has no `import Markdown`) feeds the size-1 token cache `parsedDocument(for:)`; the Apple swift-markdown `Document(parsing:)` is parsed independently and **never cached**. Collapsing both behind one cached spine keyed on text is the #9 fix.

**All 8 in-engine `Document(parsing:)` call sites:**
- `Styling/AppleASTSupplementalStyler.swift:30` — always-on supplemental parse (the prime #9 culprit; runs once per restyle on the full doc, uncached).
- `TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift:160` — `syncHeadingFolding` (2nd parse; only when `foldedHeadings` non-empty, fast-path early-return @148).
- `Renderer/MarkdownTextLayoutFragment.swift:453` — `hasBlockquoteMarker` (per-fragment, inline — the only blockquote detector, not routed through `MarkdownDetection`).
- `Parser/MarkdownDetection.swift:77` — `isThematicBreakLine` stage-2 (per-fragment via renderer @74).
- `Parser/MarkdownDetection.swift:160` — `isHeadingLine` stage-2 (per-fragment via renderer @153; per-hover via `+HeadingFoldHover:90`).
- `Parser/MarkdownDetection.swift:186` — `foldableHeadings(in: String)` one-shot overload (test + reconcile path).
- `Input/MarkdownListHandler.swift:135` — `detectListContext` (one trimmed line per Enter, regex-prefiltered @115).
- `Parser/MarkdownPlainText.swift:21` — `extract(from:)` (app word-count; no in-engine caller; sole consumer `PageTextStats.swift:36`).

Per-fragment cost: the renderer triggers up to 3 Apple parses per visible fragment per layout pass (`:453` direct + `:77` + `:160` via Detection), multiplied across fragments and relayouts.

**`parsedDocument(for:)` — defined `+Restyling.swift:146`; 12 callers:**
- `ContextMenu.swift:243`, `:251`
- `+Restyling.swift:48` (rebuild), `:245` (`restyleParagraphs`)
- `+Services.swift:189`, `:194`, `:202`, `:212`, `:420`
- `+TextDelegate.swift:108` (textDidChange), `:184` (selection), `:365` (shouldChangeTextIn)

Cache state: `cachedParsedText`/`cachedParsedDocument` @`NativeTextViewCoordinator.swift:136-137`; written only @`+Restyling.swift:188-189`; read @`:147-148` and (external) `+HeadingFolding.swift:38`. **No invalidation hook** — staleness handled implicitly by exact-string inequality. It is a **size-1 memo**: `shouldChangeTextIn:365` (pre-edit string) and `textDidChange:108` (post-edit string) within one keystroke thrash it → two full regex parses per keystroke.

**Raw `MarkdownTokenizer.parseTokens` calls that bypass the cache:** `MarkdownStyler.swift:98` (fallback when `precomputedTokens` nil), `MarkdownInputHandler.swift:78/197/215`, `MarkdownDetection.swift:330/395/411` (slow `in:String` overloads), `MarkdownListHandler.swift` (via `MarkdownDetection`).

#### B. Every `isInside*` caller

Two families: **slow re-parsing** `MarkdownDetection` `in:String` overloads (each calls `parseTokens` internally) vs **fast token** overloads (`codeTokens:`/`latexTokens:`), plus **cache-backed coordinator wrappers** (`+Services.swift`) that delegate to the fast overloads via `parsedDocument`.

Definitions (`Parser/MarkdownDetection.swift`): `isInsideCodeBlock` slow `:329`, slow `:336`, fast `:341`, fast `:355`; `isInsideWikilink` `:367` (pure line-scoped depth scan, NO parse); `isInsideLatex` slow `:394`, fast `:400`; `isInsideInlineLatex` `:410`/`:415`/`:419`/`:433` (**grep-confirmed dead outside the file** — only internal wrappers reference them). Coordinator wrappers (`+Services.swift`): `isInsideCode :188`, `isInsideLatex :193`, `isInsideSpellcheckSuppressedToken :201/:211`.

Callers:
- `NativeTextView+SpellingPolicy.swift:19/20/26/27/32` — coordinator path with slow-static fallback on nil coordinator.
- `MarkdownInputHandler.swift:81` — slow `range:in:`.
- `MarkdownListHandler.swift:381`, `:416` (slow `isInsideCodeBlock`, behind `contains("`")` prefilter), `:547` (`isInsideWikilink`, the en-dash carve-out).
- `MarkdownStyler.swift:369`, `:409`, `:532` and styler extensions `+TextStyling:67`, `+Links:35/47/86`, `+Images:20`, `+Latex:21/65` (fast `codeTokens:`).
- `+Services.swift:154/156/160/162` (autocorrect), `:478/:488` (`inlineTokenContext`).
- `+HeadingFolding.swift:49` (`isFragmentRangeInsideCodeBlock`).
- `+HRVisibility.swift:219-222` — note `isInsideCodeBlockParagraph` (`:230`) is a **separate color-match check**, not a `MarkdownDetection` call.
- Renderer `MarkdownTextLayoutFragment.swift:132` → `coordinator.isFragmentRangeInsideCodeBlock` (the one cache read from the fragment).

#### C. The styler chain (primary vs supplemental)

**Primary** `MarkdownStyler.styleAttributes` (`MarkdownStyler.swift:86`) — regex-token, caret/active-token-aware. **Supplemental** `AppleASTSupplementalStyler.styleAttributes` (`AppleASTSupplementalStyler.swift:25`) — Apple-AST, caret-UNaware, covers BlockQuote/Strikethrough/Table (ThematicBreak = no-op @248-262).

**Two composition sites** (supplemental always runs AFTER primary, additive):
- **Per-edit:** `TextStylingService.restyle` — primary @`TextStylingService.swift:70` (scoped to paragraphs), supplemental @`:88` (whole-doc, NO scope), merged `primaryStyledRanges + supplementalRanges` @`:94`, applied paragraph-clipped via `NSIntersectionRange` @`:116`.
- **Full-rebuild:** `rebuildTextStorageAndStyle` — primary @`+Restyling.swift:56`, supplemental @`:71`, merged + applied **UNSCOPED** over the whole doc @`:76`. This path does NOT route through `TextStylingService.restyle`; it hand-rolls its own apply loop. Two independent apply implementations of "reset base then layer ranges."

Both paths re-sync HR + heading folding afterward (`+Restyling.swift:101-104` rebuild, `:140-143` per-edit). The styler emits nothing for ThematicBreak; HR is owned solely by `syncHRVisibility`.

#### D. The save/write fan-out

The engine performs **no disk write**. Its sole upstream surface is `@Binding var text` (`NativeTextViewCoordinator.swift:28`). Persistence is the host's job (`PageEditorViewModel.body` didSet → 300ms debounced `PageFile.save` → `AtomicYAMLMarkdown.write(preservingFrom:modeledKeys:)`; frontmatter preserved entirely app-side).

**Binding write sites (the "save"):**
- `+TextDelegate.swift:70` — `self.text = storageState.storage`, inside a `DispatchQueue.main.async` @68, gated by `if !wtActive` @60 and the `lastSyncedText` dedup @67. Line 61 *computes* via `WikiLinkService.makeStorageState`; **line 70 writes** (D14 in the old docs cited :61, which is wrong).
- `+Services.swift:325/338` — Writing-Tools session-end save (2nd path; mutually exclusive with #1 by WT-active gating; uses `makeStorageState` then writes `lastSyncedText`/`text`).
- `ContextMenu.swift:140/167/186/211/227/281/317/352/410/432` — **10 raw `self.text = tv.string` writes** that BYPASS `makeStorageState` and the `lastSyncedText` dedup (asymmetry: could persist display-form `[[Name]]` without IDs if IDs ever existed).
- 3rd mutation path: `rebuildTextStorageAndStyle` rewrites `textView.string` + `lastSyncedText` directly (not the binding) on the WT-undo branch.

### Change-Site Table per Phase

#### Phase 1 — Re-home / rename

| What | file:line | Current behavior | Risk |
|---|---|---|---|
| Rename SPM package + product `MarkdownEngine` → `MarkdownPM` | `Package.swift:24-42` | name/product/target = `MarkdownEngine`; testTarget `MarkdownEngineTests` | Product name is the import symbol; must land atomically with all import edits |
| Update pbxproj reference | `project.pbxproj:611-614` (relativePath), `:650-654` (productName), `:11/:64/:129/:220` | `relativePath=../External/MarkdownEngine`; `productName=MarkdownEngine` | Hand-edit error-prone; Xcode auto-reorders SPM entries on build (revert noise) |
| `import MarkdownEngine` → `import MarkdownPM` in 3 app files | `PageTextStats.swift:2`, `PageEditorViewModel.swift:2`, `PageEditorView.swift:2` | 3 app imports | Atomic with product rename |
| Same in 2 test files | `PageTextStatsTests.swift:8`, `FoldableHeadingsTests.swift:2` | resolve via host-app link, no direct PommoraTests dep | brittle — see P2 wiring fix |
| Re-home all engine source files; keep `NativeTextViewWrapper.Coordinator` alias intact | `NativeTextViewWrapper.swift:23`; alias referenced in `ContextMenu.swift:13,438`, `MarkdownListHandler.swift:22,24`, `MarkdownInputHandler.swift:174,178` | internal alias; same-module | Internal; verify after re-home |
| Preserve runtime attribute-key string literals | `MarkdownToken.swift:14` (`"NodeLinkID"`), `:15` (`"TaskCheckbox"`); latex keys `MarkdownTextLayoutFragment.swift:17-20` | Swift symbol `wikiLinkID` ≠ literal `"NodeLinkID"` | Renaming literal breaks styler/renderer/toggle/`makeStorageState` silently |
| Keep `StyledRange` typealias resolvable | defined `MarkdownStyler.swift:79`; used in `AppleASTSupplementalStyler.swift:29`, `TextStylingService.swift` | cross-file typealias | Re-homing AppleASTSupplementalStyler in isolation breaks |
| `makeNSView` fatalErrors if no TextKit2 stack | `NativeTextViewWrapper.swift:140` | hard crash, not graceful | Module/OS-target change must keep TextKit2 available |

#### Phase 2 — Characterization test net

| What to pin | file:line | Current coverage | Risk |
|---|---|---|---|
| Wrapper 15-param init defaults + 7-used/8-dormant contract | `NativeTextViewWrapper.swift:85-101`; contract `PageEditorView.swift:210-222` | none | greenfield |
| Per-keystroke parse counts (regex ~1, Apple 1-2) | `+Restyling.swift:146-191`; `AppleASTSupplementalStyler.swift:30`; `+HeadingFolding.swift:160` | none; #9 observed as stutter not asserted | `Document(parsing:)` is a free func — needs a call-count probe; cover BOTH folded + unfolded baselines |
| Save dedup + storage-form value + WT proofread skip | `+TextDelegate.swift:52,60-72`; `+Services.swift:312-340` | none | WT paths are macOS-15 delegate callbacks; characterize at `makeStorageState`/`applyHRSync` seam |
| Exact `[N]` fold-key strings + CRLF/LF + contentRange + `shouldEnumerate` elision + YAML round-trip | `MarkdownDetection.swift:264-274`; existing seed `FoldableHeadingsTests.swift`, `PageFileTests.swift:71-117` | foldableHeadings/reconcile only; key ordinal/CRLF/contentRange/elision UNTESTED | D4-locked on-disk format; gates P3/P4 |
| All `MarkdownDetection` predicates (HR/dashBullet/heading/wikilink/`computeActiveTokenIndices`) incl. empty-`[]` 3-class split, inclusive-boundary, setext suppression | `MarkdownDetection.swift:62,95,144,367,293,313-320` | near-zero | subtle byte/stage logic regresses silently |
| Emphasis golden output (rule-of-3, intra-word, nested `***`, cross-line, flanking, **asterisk-only/no underscore**, no code dedup) | `MarkdownTokenizer+Emphasis.swift:13-156` + `:138-146` | zero | blind deletion otherwise; pin asterisk-only + no-overlap as intentional |
| Math/currency thresholds (120/40/6, 1-3-letter math, currency=money) | `MarkdownTokenizer.swift:210-240` | none | money/math split easy to regress |
| The 9 input transforms (byte-level golden), order, `--`-before-fast-path, `-` fast-path inclusion, wikilink carve-out | `MarkdownListHandler.swift:358-561`; `detectListContext:97-224` | none reachable | needs live @MainActor NSTextView host; XCTest launch-modal guard |
| Styler `StyledRange` golden (code/inline-code/checkbox active+inactive/incomplete-bracket/shrink); primary-before-supplemental order; clipping both paths; ThematicBreak emits zero | `MarkdownStyler.swift:86-187`; `TextStylingService.swift:70-122`; `+Restyling.swift:56-80` | none direct | needs deterministic fake `SyntaxHighlighter`; two apply mechanisms differ at paragraph boundaries |
| AppleAST emit attrs for 4 constructs incl. UTF-8→UTF-16 multibyte/CRLF + separator-row math | `AppleASTSupplementalStyler.swift:58-262,272-377` | none | multibyte/CRLF range mis-placement |
| OS-workaround behaviors (FB22524198 caret-Y, block-image caret, marked-text restyle, paste sanitize, checkbox toggle, overscroll height, click-remap, chevron) | `NativeTextView+*` (see Keep-Verbatim) | only `EnterContinuationTests.swift` engine-side, `PageTextStatsTests` app-side | NSTextInsertionIndicator is KVO/private; mostly manual-verify |
| **Test-run wiring:** engine tests not in Pommora scheme | `Pommora.xcscheme:32`; `project.pbxproj:154` (PommoraTests dep = GRDB only) | `MarkdownEngineTests` never run by `xcodebuild test -scheme Pommora` | **P2 false-green trap** — add `swift test`/test-plan; add `MarkdownPM` to `PommoraTests.packageProductDependencies` (currently resolves via host-app link only) |

#### Phase 3 — Single cached parse spine (#9)

| What | file:line | Current behavior | Risk |
|---|---|---|---|
| Cache the Apple `Document` alongside regex tokens; feed supplemental styler from cache | extend `ParsedDocument` `NativeTextViewCoordinator.swift:143`; `parsedDocument(for:)` `+Restyling.swift:146-191`; consumer `AppleASTSupplementalStyler.swift:30` (sig takes `text`, not a Document) | 12 token call sites + 1 external field reader; supplemental re-parses full doc every restyle | HIGH — struct-contract change; supplemental signature change touches both composition sites; cache must hold a non-equatable Document keyed on text |
| Route `syncHeadingFolding` Apple parse through the cache; keep `foldedHeadings.isEmpty` fast-path | `+HeadingFolding.swift:158-161` (own parse), `:148` (fast-path) | folded page double-parses (tokens + AST) per edit | Medium — same coordinator owns cache; `lineIndex` overload already exists to share |
| Delete slow `in:String` `isInside*` overloads; thread cached tokens to fallback callers | `MarkdownDetection.swift:329-338,394-398,410-417`; callers `SpellingPolicy:20/27`, `+Services:156/162`, `MarkdownListHandler:381/416`, `MarkdownInputHandler:81` | each re-tokenizes from raw string when no coordinator/tokens | Medium — fallbacks fire on nil coordinator; **KEEP `isInsideWikilink`** (line-scoped counter, en-dash guard) |
| Remove raw `parseTokens` bypass calls; thread `precomputedTokens` everywhere | `MarkdownInputHandler:78/197/215`, `MarkdownDetection:330/395/411`, `MarkdownStyler:98` (fallback) | extra full re-tokenizes; `shouldChangeTextIn` parses PRE-edit string | Medium — verify pre/post-edit text identity (`pendingPreEditActiveTokenIndices` depends on the two-parse model) |
| De-dupe per-fragment renderer detection through coordinator-supplied block-type lookup | `MarkdownTextLayoutFragment.swift:74,153,453,727-811` (bounds duplicates draw) | up to 3 AST parses/fragment, doubled by `renderingSurfaceBounds` | HIGH — per-fragment isolation is deliberate (avoids `.pommoraThematicBreak` attribute-inheritance leak, `:62-70`); must not reintroduce attribute-based detection |
| Route `WikiLinkService` regex scans / the wrapper's parse-skip gate through the spine | `WikiLinkService.swift:54-55,70,122`; gate `NativeTextViewWrapper.swift:336-338`, rebuild call `:376` | `makeDisplayState`/`makeStorageState` re-scan whole doc on load/edit/restyle/WT; fold-fast-path @343-345 runs without reparse | Med-High — transform's UTF-16 bookkeeping must match parser ranges; preserve the fold-only fast path |

#### Phase 4 — Apple-AST inline locating + delete emphasis parser

| What | file:line | Current behavior | Risk |
|---|---|---|---|
| DELETE `MarkdownTokenizer+Emphasis.swift` (173 LOC) + its one call | whole file `:12-173`; call `MarkdownTokenizer.swift:58` | hand-rolled stack parser, **asterisk-only, no underscore, no code-overlap dedup**, sole producer of `.italic/.bold/.boldItalic` | HIGH — Apple AST adds `_underscore_` + resolves inside-code differently; AST must reproduce `range/contentRange/markerRanges` for `styleEmphasis` per-char trait merge (`+TextStyling.swift:50-99`) |
| Decide fate of `.italic/.bold/.boldItalic` enum cases | `MarkdownToken.swift:19-21` | only emphasis parser emits them | HIGH — removing forces module-wide exhaustive-switch fixes; re-emitting from AST is lower-risk |
| Reconcile heading-regex divergence to one AST rule | `MarkdownTokenizer.swift:23-26` (`#{1,6} +`, requires space) vs `MarkdownDetection.swift:155` (`#{1,6}([ \t]\|$)`, space/tab/EOL) + AST walk `:160` | three heading detectors disagree on bare `#`, tab-separated, trailing-space-only | Med-High — pick CommonMark (space/tab/EOL) so styler + fold agree |
| Hoist duplicated fold-key computation to one source | `+HeadingFolding.swift:65-82` (`disambiguatedHeadingKey`) duplicates `MarkdownDetection.swift:264-274` | two impls of `[N]` ordinal rule (renderer key + hover hit-test) | Medium — must stay byte-identical or fold membership desyncs |
| Migrate inline locating (`inlineTokenContext`, link/wikilink/image edges) to AST or keep regex for Pommora syntax | `+Services.swift:471-493`; `MarkdownStyler+Links/+Images`; `WikiLinkService.swift:50-55,184-198` | wiki-links/image-embeds are regex-token-based, hardcode `loc+2`/`max-2`/openMarker=3 | HIGH — **Apple AST does NOT model `[[...]]` or `![[...]]` or LaTeX**; these must STAY regex; preserve inner-edge caret semantics for popover anchor |
| Math/LaTeX passes have NO AST equivalent — keep as Pommora supplemental pass | `MarkdownTokenizer.swift:170-187,210-240` | `isInlineMathContent` is sole `$5`-vs-`$x+y$` gate; swift-markdown has zero math | HIGH — "delete all regex passes" would silently drop math rendering |
| Strikethrough already AST-located — fold into unified inline visitor, keep coverage | `AppleASTSupplementalStyler.swift:163-177` | GFM Strikethrough via default ParseOptions | Low — state explicitly so no regression |

#### Phase 5 — One owned styler + theme

| What | file:line | Current behavior | Risk |
|---|---|---|---|
| Merge primary + supplemental into one styler; preserve last-writer-wins-per-key + sub-styler order | `MarkdownStyler.swift:86` + `AppleASTSupplementalStyler.swift:25`; composition `TextStylingService.swift:94`, `+Restyling.swift:76` | concatenation order = implicit conflict policy; supplemental overrides primary | HIGH — divergent signatures (primary caret-aware + scoped; supplemental caret-unaware + whole-doc); must keep initial-load unscoped completeness + per-edit clipping; decide BlockQuote/Table marker caret-reveal (behavior change) |
| Hoist hardcoded code-text color `systemRed@0.85` to one theme token | `MarkdownStyler.swift:462` + `:499` (two copies, both in-file) | no theme token; background already service-sourced (asymmetry) | Medium — default token to exactly `systemRed@0.85`; DRY fix |
| Wire a real `WikiLinkResolver`; resolve D1 id-on-disk policy | `MarkdownStyler+Links.swift:55-69`; seam `MarkdownEditorServices.swift:233,240`; gap `PageEditorView.swift:351-355` | `NoOpWikiLinkResolver` → all wikilinks render `disabledText`, never `.link`; **no id ever written, only by absence — no guard** | HIGH — injecting any id-returning resolver silently begins persisting `[[Name\|id]]` to user .md; D1 must be explicit |
| Migrate brand-meaningful renderer literals into config/theme (D17) | `MarkdownTextLayoutFragment.swift:303-304` (HR `separatorColor`/1.5), `:567-568` (bar 4/radius 6), `:639` (card `tertiarySystemFill`), `:655` (bar `secondaryLabelColor`), `:383` (bullet 1.5×), `:1136/1159` (checkbox factors hardcoded vs `CheckboxStyle`) | not in config; embedders can't retheme; pixel-snap coupled to barWidth/cornerRadius | HIGH — exact transplant or visual regression; bullet-1.5× ↔ checkbox-alignment coupling (`:1144-1146`) must survive geometry/color split |
| Preserve HR sole-writer invariant + AppleAST ThematicBreak no-op through consolidation | `+HRVisibility.swift`; `AppleASTSupplementalStyler.swift:248-262`; `MarkdownStyler.swift:179-183` | service is sole HR writer; styler emits nothing | HIGH — re-introducing an HR-specific persisted attribute revives "duplicate HR on every Enter" (`MarkdownTextLayoutFragment.swift:21-28`) |
| Unify find-highlight strength source | `MarkdownEditorTheme.swift:90-91` (identical `.systemYellow`) + `MarkerStyle.findMatchHighlightAlpha` `MarkdownEditorConfiguration.swift:158` | two colors, strength via alpha in a different sub-struct | Low — cosmetic decision |
| Move `HeadingHelpers` + `appendRenderedStandaloneBlock`/`appendSecondaryMarkers` into owned styler; merge duplicate list regexes | `HeadingHelpers.swift:11-54`; `MarkdownStyler.swift:194-356`; `MarkdownListHandler.swift:340,349` vs `:32` | shared measurement math + standalone-image collapse split across files; duplicate bullet regexes | Medium — collapse math is pixel-exact; bullet patterns are NOT byte-identical (extra content group) |

#### Phase 6 — Body-orchestration tidy + verbatim transplant

| What | file:line | Current behavior | Risk |
|---|---|---|---|
| Tidy `make/updateNSView` bodies; preserve guarded early-return ORDER | `NativeTextViewWrapper.swift:119-253,255-396` (WT guard `:264-273`, pendingInlineReplacement `:307-318`, fold-fast-path `:336-347` all return before rebuild `:376`) | imperative; order-dependent | Medium — reorder → double-reparse / lost fold path / WT overwrite |
| Extract shared `parse→activeTokens→restyle` preamble | `+TextDelegate.swift:108-150,184-238`; `restyleParagraphs` `+Restyling.swift:244-254` | duplicated edit vs caret-only sequences | Medium — over-merge regresses caret-only HR sync `:339-346` |
| Unify save into one `notifyTextChanged`/`syncBodyTextOut` helper; reconcile ContextMenu raw writes | `+TextDelegate.swift:42-52,60-72`; `ContextMenu.swift:140/167/186/211/227/281/317/352/410/432` | 11 binding-write sites; 10 bypass `makeStorageState`+dedup | Medium — unifying could change persisted wikilink form (storage vs display); **flag for design review** |
| Unify the two apply blocks (rebuild unscoped vs per-edit clipped) | `+Restyling.swift:44-81` vs `TextStylingService.swift:105-127` | two sources of "reset base then layer ranges" | Medium — must preserve initial-load completeness vs paragraph clipping tension |
| Keep HR-before-folding sync order on both paths; remove dead empty else | `+Restyling.swift:140-143`; dead block `+HeadingFolding.swift:195-196` | dual-site sync; dead else | Low |
| Remove dead `taskListRegex` + no-op expression in tokenizer | `MarkdownTokenizer.swift:27-30,134` | declared/never used; computed-and-discarded | Low (live divergent copy in `MarkdownStyler.swift:43`) |
| `mouseDown` dispatch order is load-bearing (checkbox→remap→chevron→boost→super) | `NativeTextView+DragSelectBoost.swift:14-39` | early-return chain | Medium — checkbox/chevron must consume click before super repositions caret |
| Build the **unbuilt** Fix Log #8 backspace-on-checkbox syntax-delete | new path in `MarkdownListHandler`/`MarkdownInputHandler` | NO such code exists anywhere | Medium — new work, scope unspecified (whole marker vs step-through) |
| `MarkdownPlainText` stays single rendered-prose source | `MarkdownPlainText.swift:14-48`; consumer `PageTextStats.swift:36,41` | sole stripper | Low |

### Claims-Verification Ledger

This is the authoritative record of what old-doc/focus claims to trust vs discard. Lead with WRONG, then REFINED, then CONFIRMED.

#### WRONG — corrected value + evidence (discard the old claim)

1. **"D20 says the wrapper init has 14 params."** TRUE = **15** params (7 used + 8 dormant). `NativeTextViewWrapper.swift:86-100`. D20 undercounts by one (likely missed `onLinkClick` @96). 7-used is correct.
2. **"ParsedDocument holds an Apple swift-markdown Document."** It holds **only six regex `[MarkdownToken]` arrays** (`NativeTextViewCoordinator.swift:143-150`); the main file doesn't `import Markdown`. Apple Document is parsed outside the cache (`AppleASTSupplementalStyler.swift:30`, `+HeadingFolding.swift:160`).
3. **"The save/body-text write is at `+TextDelegate.swift:61`."** Line 61 *computes* `makeStorageState`; the **write is `:70`** (`self.text = storageState.storage`), gated by dedup `:67` and `!wtActive` `:60`.
4. **"The supplemental styler is scoped to the same paragraphs as primary (per-edit)."** Supplemental gets the **FULL `textView.string`, NO scope** (`TextStylingService.swift:88`); only apply-time clip `:116`. It walks the whole doc every keystroke.
5. **"`parsedDocument(for:)` is the single cached parse spine for the whole pipeline."** It caches **only regex tokens** for opt-in callers; supplemental + heading-fold + renderer bypass with their own `Document(parsing:)`. Three independent parse mechanisms.
6. **"`rebuildTextStorageAndStyle` routes through `TextStylingService.restyle`."** It does NOT — it calls the stylers directly (`+Restyling.swift:56,71`) and hand-rolls its own `beginEditing/addAttribute/endEditing` block. Two apply implementations exist.
7. **"The dual-styler merge exists in exactly one place."** TWO sites: `TextStylingService.swift:94` (per-edit, paragraph-scoped, with spelling pre-pass) and `+Restyling.swift:76` (full-rebuild, whole-range, NO spelling pre-pass, single full-range base reset).
8. **"AppleASTSupplementalStyler covers ThematicBreak."** `visitThematicBreak` (`:248-262`) is a deliberate **no-op** (`_ = thematicBreak`); covered constructs are BlockQuote/Strikethrough/Table. Header comment overstates coverage.
9. **"`StyledRange` is defined in `AppleASTSupplementalStyler.swift`."** Defined in `MarkdownStyler.swift:79`; the supplemental file only consumes it.
10. **"Emphasis tokenizing happens in `MarkdownTokenizer.swift`."** Only the **call** is there (`:58`); the entire implementation is `MarkdownTokenizer+Emphasis.swift:13-172`. No emphasis regex exists in the static bank.
11. **"The emphasis parser supports underscore (`_`) emphasis."** **Asterisk-only** — `MarkdownTokenizer+Emphasis.swift:62` matches `0x2A` only; no `0x5F`. Real behavior GAP vs Apple AST.
12. **"Emphasis tokens are de-duplicated against overlapping code/LaTeX ranges at parse time."** No overlap guard; appended FIRST with no exclusion list (`MarkdownTokenizer.swift:58`). `*emph*` inside inline code still tokenizes as emphasis.
13. **"There is non-emphasis code in `MarkdownTokenizer+Emphasis.swift` that must survive D7."** Every line is emphasis-only; nothing survives. Dependent types (`MarkdownToken`/`MarkdownTokenKind`) live in `MarkdownToken.swift`.
14. **"`parseEmphasisTokens` has more than one caller."** Exactly one (`MarkdownTokenizer.swift:58`).
15. **"`isInsideInlineLatex` family is actively used."** **Grep-confirmed DEAD** outside its file (only internal wrappers reference `MarkdownDetection.swift:410-435`). The live latex predicate is `isInsideLatex`. Removable.
16. **"The slice's 4 MarkdownStyler+ extension files perform SourceRange→NSRange conversion."** They do NOT; they operate on already-NSRange tokens. The converter (`SourceRangeConverter`) lives in `AppleASTSupplementalStyler.swift:271`, used by AppleAST styler + `MarkdownDetection`. The conversion concern is out of that slice.
17. **"`HeadingHelpers` is a `MarkdownStyler` extension."** It's a standalone `enum HeadingHelpers` (`HeadingHelpers.swift:11`), not an extension.
18. **"`styleEmphasis` simply applies a font per token (overwrites)."** It builds a per-char `UInt8` trait array and OR-merges contiguous runs so nested `**`/`*` combine (`+TextStyling.swift:55-97`). Load-bearing.
19. **"NOTICE.md's '6 extensions' = 6 sibling files."** Only **4** sibling `MarkdownStyler+*.swift` files exist; the other 2 (`+Code`, `+TaskCheckboxes`) are inline extension blocks inside `MarkdownStyler.swift`. (As `extension MarkdownStyler {}` blocks there are 10 total.) Neither doc is wrong once "file" vs "logical extension" is distinguished.
20. **"The 9 input transforms live in `MarkdownInputHandler.swift`."** They live in **`MarkdownListHandler.swift` (`MarkdownLists.handleInsertion`, `:358-898`)**. `MarkdownInputHandler` is a facade + Pommora char-pair/auto-wrap extras.
21. **"Smart-quotes is an engine-owned transform."** Delegated to **macOS** (`isAutomaticQuoteSubstitutionEnabled=true`, `NativeTextViewWrapper.swift:188`); only auto-dash is forced OFF (engine owns dashes). No straight→curly quote code exists.
22. **"`handleInsertion` handles only list input."** It is the entire keystroke cascade: em-dash, arrows, en-dash, brackets, bracket-skip, code-fence, blockquote, AND list continuation (`MarkdownListHandler.swift:366-833`).
23. **"Fix Log #8 (backspace-on-checkbox syntax-delete) is existing behavior."** **UNIMPLEMENTED** — zero such code; it's a TODO at `Handoff.md:58`. Must be BUILT (new P6 site).
24. **"Code-block background detection uses an AST guard like the other constructs."** It uses **color-comparison** against the highlighter background (0.03 tolerance, `MarkdownTextLayoutFragment.swift:1005-1018`) — intentionally, because the styler-applied attribute is the source of truth (`:113-121`).
25. **"`isHeadingLine` lives in MarkdownTokenizer."** It's in `MarkdownDetection.swift:144`. The tokenizer's heading detector (`headingRegex`) is a different, stricter rule.
26. **"PommoraTests directly depends on MarkdownEngine."** Its `packageProductDependencies` = **GRDB only** (`project.pbxproj:154`); the 2 test imports resolve transitively via the host app (`TestTargetID=Pommora` `:199`). Brittle/undocumented.
27. **"`MarkdownToken`/`ParsedDocument` etc. carry symbol-level dependency edges in the graphify graph."** The manifest is file-keyed/build-artifact level only; **no call edges**. All edges in this report are source-grep-verified. (Graph built from commit `e36e8b40`; HEAD is `363fedc` — stale.)
28. **"`isWikiLinkActive`/`pendingInlineReplacement`/`onInlineSelectionChange` are part of `MarkdownEditorServices` (the services seam)."** They are `@Binding`/closure params on `NativeTextViewWrapper` (`:33,36,73`), the SwiftUI seam — and the app wires NONE of them (all default inert).
29. **"MarkdownPlainText and MarkdownToken are on the same parse pipeline."** Different pipelines: `MarkdownToken` = legacy regex tokenizer; `MarkdownPlainText.extract` rides the Apple AST (`MarkdownPlainText.swift:21`) and never references `MarkdownToken`.
30. **"`![[...]]` image embeds are handled by the WikiLinkService transform."** Both regexes use `(?<!!)` lookbehind (`WikiLinkService.swift:50,52`) **excluding** image embeds; handled by a separate `EmbeddedImageProvider` path.
31. **"`MarkdownDetection.foldableHeadings` is called by app production code (this slice)."** App production calls only `reconcileFoldedHeadings` (`PageEditorViewModel.swift:92`); `foldableHeadings` is test-only app-side + engine-renderer internal.

#### REFINED — adjusted understanding (trust the corrected nuance)

- **149pt height-oscillation guard:** observer **registered** at `NativeTextViewWrapper.swift:219`; the actual `abs>1` guard is **line 231**; comment `:229-230`. **No boolean re-entrancy flag** — two captured-local epsilon gates (width `>0.5` @222 via `lastObservedViewportWidth` @218; height `>1` @231).
- **`isWikiLinkActive`/`pendingInlineReplacement`:** these are **`@Binding`s, not closures** (`:33`, `:36`), and **DORMANT** (no app reference). Several other "closures wired by the app" claims (`onInlineSelectionChange`, `onPasteImage`, `onCaretRectChange`, `onCodeBlockSelectionChange`) are real closures but DORMANT. Only `onScrollOffsetChange` is wired (`PageEditorView.swift:217`).
- **`parsedDocument(for:)` cache:** it's a **size-1 memo** keyed on exact full-string equality with **no invalidation hook** (`+Restyling.swift:147`); pre-edit (`:365`) vs post-edit (`:108`) texts in one keystroke thrash it → two regex parses.
- **"Document parsed twice/thrice per keystroke."** Regex tokenizer runs ~once (cache-deduped); the redundant work is the **Apple parser running 1× (no folds) to 2× (folds active), uncached**, plus raw tokenizer bypasses. #9 is primarily redundant uncached Apple-AST parsing, not a token-cache failure.
- **`parsedDocument(for:)` "single shared entry."** Shared for the **regex-token parse only**, for the 12 opt-in sites; two Apple-Document sites + several raw tokenizer calls bypass it.
- **`textViewDidChangeSelection` "re-styles per caret move."** Re-parses every selection change (`:184`) but restyles **only** when `tokensChanged && !pendingEditedRange` (`:233-239`); scoped HR sync on caret-only moves (`:339-346`).
- **`shouldEnumerate` fold-elision "at ~line 475, returns nil."** The conformance is `+HeadingFolding.swift:516-544` (returns Bool); `~475` is the comment block; the **nil-return is the sibling `textParagraphWith` (`:551-556`)**, which SIGTRAPs if it substitutes a length-mismatched paragraph.
- **"Renderer + service agree on fold-key by construction."** Agreement is by **DUPLICATED rule** (`+HeadingFolding.swift:65-82` mirrors `MarkdownDetection.swift:264-274`), not a single source — the P4 DRY site.
- **"`isInsideWikilink` is used by the em-dash transform."** It's the **en-dash** (`–`, U+2013) transform (`MarkdownListHandler.swift:547,552`); the "em-/en-dash" phrasing is loose. Only en-dash uses this guard.
- **Em-dash "must run before fast-path so it re-breaks `---`."** Two facts: (1) the order IS load-bearing (em-dash block `:361-391` is above the fast-path `:395`); (2) the `---` handling is a **hrConflict PRESERVE guard** (`:376-378`) — it does nothing to `---`, not "re-breaks."
- **"Auto-pairing is Nathan-added."** TWO systems: char-pair auto-pair/delete in `MarkdownInputHandler` IS Pommora-added (v0.2.7); the single-bracket `[ ( {` auto-pair inside `handleInsertion:564-613` is original. They overlap on `[`.
- **"The regex tokenizer produces tokens for headings, links, lists, code, LaTeX."** 11 kinds, NO list/task-list kind; `taskListRegex` (`MarkdownTokenizer.swift:27`) is declared but never invoked (dead).
- **Math heuristic thresholds 120/40/6:** keyed on count of "mathy" chars (≥3→≤120 whitespace tokens, ==2→≤40, ==1→≤6); a 1-3-letter run with 0 mathy chars IS treated as math (`$x$`, `$ab$`); pure numbers are money. `MarkdownTokenizer.swift:214-237`.
- **`MarkdownEditorTheme` "all system colors."** 8/12 are dynamic system colors; **4 are fixed literals**: `headingMarker=.gray`, `latexLightModeText=.black`, `latexDarkModeText=.white` (`MarkdownEditorTheme.swift:86,92,93`).
- **`HeadingStyle` "pure value sub-struct."** The **only** sub-struct with behavior (clamp+lookup helpers `MarkdownEditorConfiguration.swift:264-272`).
- **`MarkdownEditorServices` "is the services seam the app touches."** The seam exists and the engine consumes it, but the app **never touches `config.services`** (uses `.default`, all No-Op).
- **Wiki-link transform "round-trips plain `[[Title]]`."** Bidirectional `[[Name|id]]`↔`[[Name]]`; in the live app there's never an id, so it round-trips plain. Machinery has zero live producers.
- **"Save fires on every keystroke."** Per-keystroke for normal typing only; gated by `!isWritingToolsActive` (`:60`) + `lastSyncedText` dedup (`:67`); proofread early-returns (`:52`).
- **"Engine OWN tests are broad."** Single file, two suites (`EnterContinuationTests` + `CheckboxCanonicalizationTests`); covers only Enter-continuation + checkbox canonicalization.
- **"There are two `isInside*` callers in MarkdownListHandler."** THREE total (`:381`, `:416` `isInsideCodeBlock`; `:547` `isInsideWikilink`). "x2" is correct only for the deletable slow `isInsideCodeBlock` overloads.
- **"There are 17 config sub-structs."** **18 stored properties** = theme + services + **16 inline value sub-structs**; `services` type lives in a separate Services file (excluded from the 16).
- **"Block constructs the supplemental styler covers."** 3 block types (BlockQuote/Table emit; ThematicBreak no-op) + 1 **inline** (Strikethrough) — "block constructs" is imprecise.
- **"`MarkdownToken` is frozen-by-tests, not a public promise."** Correct that it's implicitly internal + no app references; refine that the two attribute keys (`.wikiLinkID`/`.taskCheckbox`) ARE public (so the slice has THREE public symbols, not one), but consumed only intra-module.
- **"Magic byte-codes appear in blockquote/table walks."** Blockquote walks + dash-bullet marker walk only (`MarkdownTextLayoutFragment.swift:355-357,441-450,517-525`); **there is NO table-rendering code** in the slice.
- **"`styleAttributes` would take a pre-parsed Document if handed one."** It must STILL receive `text`/`nsText` (NSString length, substring/pipe scanning, byte→UTF16 conversion) — the Document alone is insufficient.
- **"The Document parse enables GFM Strikethrough/Table."** Correct, but **implicit** — `:30` passes NO `ParseOptions`; relies on swift-markdown defaults. A re-home must not introduce custom options disabling GFM.
- **"Caret-aware: primary yes, supplemental no."** Confirmed; refine that BlockQuote/Table marker collapse is gated only by trailing space/tab, NOT caret — consolidation must decide whether to add caret-reveal (behavior change).
- **"`MarkdownLists.handleInsertion` re-parses Markdown per keystroke."** Parses **one pre-trimmed line** (not whole doc) per Enter (`:135`), regex-prefiltered.
- **"`isDashBulletLine` participates in the empty-`[]` two-class divergence."** It's a **third, narrower class** — a `-`-only glyph detector that returns FALSE for any bracket-bearing marker (`MarkdownDetection.swift:124-126`). The empty-`[]` split is THREE classes (list-detection optional `?`, checkbox non-empty, dash-bullet bracket-excluding).
- **"FB22524198 caret workaround is at lines 717/1185."** Line 717 is the FB MARK header; the bridge var is `:720-721`; the seed assignment is `:1193`. The nonisolated/`assumeIsolated` shim is a separate (also keep-verbatim) concern.
- **"Every NativeTextView+ file is an OS-bug workaround."** Only CaretWorkarounds, HeadingFoldHover, DragSelectBoost, FrameAndOverscroll, and `NativeTextView.setMarkedText` carry true OS workarounds; SpellingPolicy/PasteHandling/ClickRemap are feature behaviors (no FB id).
- **"The spellingState pre-pass scans the merged set so supplemental can disable spelling."** Scans the merged set, but **only primary emits `spellingState`** (`MarkdownStyler+Latex/+Links`); supplemental never disables spelling.
- **"Bullet is 1.2× per renderer."** Bullet is **1.5×** (`MarkdownTextLayoutFragment.swift:383`); a stale comment at `:758` says 1.2× but code at `:767` uses 1.5×. Trust code.
- **"HRVisibility triggers: selection-change + restyle-after-`TextStylingService.restyle`."** Trigger (2) calls the **full-doc** `syncHRVisibility` at `+Restyling.swift:141` after `MarkdownStyler.styleAttributes` (`:56`, not a literal `TextStylingService.restyle` symbol on that path); trigger (1) uses the **scoped** variant, called from `+TextDelegate` (out of slice).

#### CONFIRMED (compact)

Wrapper: 15-param init w/ 7 used + 8 dormant; `onScrollOffsetChange` is the only app-wired closure; 4 public selection types all app-dormant. Coordinator/cache: `ParsedDocument` at `:143`; cache fields `:136-137`, written only `:188-189`, read `:147-148`+`+HeadingFolding:38`; `parsedDocument(for:)` is the shared regex entry for 12 sites. TextDelegate: per-keystroke re-tokenize+re-style; per-keystroke full-document parse; `@Binding text` is the only save mechanism in that file. Restyling: primary-before-supplemental on both paths; a parse happens here; supplemental must run on full-rebuild for initial-load completeness; HR re-synced after every pass on both paths. Folding: `syncHeadingFolding` does its own `Document(parsing:)` (only-when-folded); `[N]` ordinal + `.newlines`-trim is D4-locked on-disk; CRLF tolerance at all key sites; headings never elided (fold range starts after heading line); `foldedHeadings` is Pages-only. Services/HR: WT recovery `:281-398`; save path `:325`; two save paths share `makeStorageState`+`lastSyncedText`, mutually exclusive by WT gating; HRVisibility sole HR writer (3 files agree); duplicate-HR regression tied to a persisted attribute; `documentId` read by WT recovery for mid-session switch; `previousSpellingDisabled` dirty-guard. Tokenizer: heading detector divergence real (`MarkdownTokenizer.swift:24` vs `MarkdownDetection.swift:155`); thresholds 120/40/6; `$5`=money/`$x+y$`=math. Emphasis: finds bold/italic/boldItalic; implements rule-of-3, flanking, intra-word; token produced at `:138`; 173 deletable LOC; single caller. Detection: 3-way `isInside*` overloads exist; F2 keep-`isInsideWikilink`; `reconcileFoldedHeadings` public; HR predicate multi-call-site; checkbox empty-`[]` logic finalized 2026-06-01 + deliberate list-vs-checkbox divergence; setext-suppression via in-isolation parse; `foldableHeadings` has both re-parsing String + cache-reusing Document overloads; single cached spine exists that slow overloads bypass; `LineOffsetIndex`/`SourceRangeConverter` defined locally + reused. MarkdownToken/PlainText: `MarkdownToken`/`MarkdownTokenKind` internal; `MarkdownPlainText.extract` public + cross-module + signature `extract(from:)->String`; CodeBlock/BlockMarkup keep-verbatim. AppleAST: `Document(parsing:)` at `:30` is the always-on culprit (double unfolded / triple with folds); covers BlockQuote/Strikethrough/Table; ThematicBreak no-op. MarkdownStyler: 613 LOC primary; code + checkbox styling in-file; `systemRed@0.85` duplicated in-file at `:462`+`:499`; no code-text theme token; ~6 in-file caret spots; called from exactly the 2 restyle paths. Styler extensions: 4 sibling files; NOTICE's "6" is logical-deletion-units; reuse existing `SourceRangeConverter`; D25 reveal carve-out is in the styler (`MarkdownStyler.swift:539-546`), NOT `+TaskCheckbox`. TextStylingService merge: `primaryStyledRanges + supplementalRanges` at `:94`; plain concatenation, primary-first; a parse happens; supplemental covers BlockQuote/Strikethrough/Table. Input: Enter-continuation is Nathan-added; checkbox continues as new unchecked `[ ]`; bullet continuation preserves marker char; bracket-skip is non-byte (selection-only); macOS auto-dash forced OFF; `-` kept in slow path protects `<-`. Renderer: per-fragment blockquote parse at `:453` is separate/uncoupled-to-cache; D4 fold-key format; FB15131180 still open; `.pommoraThematicBreak` is a do-NOT-re-add comment; reaches coordinator/textview via standard TK2 chain w/ graceful nil degradation; supplemental needed on initial load. NativeTextView: FB22524198 keep-verbatim; SpellingPolicy live `isInside*` caller; `NodeLinkID`/`TaskCheckbox` exact literals (public contract); FB15131180 fixes height while FB22524198 fixes Y; deinit invalidates caret KVO. WikiLink: transform is LIVE on load/restyle/save; ZERO resolver conformances in app; every link saved as plain `[[Title]]`; no id ever written (by absence, no guard); opaque id treated as foreign verbatim. App wiring: exactly 3 app + 2 test imports; `XCLocalSwiftPackageReference`; frontmatter preservation lives APP-side; engine OWN tests not run by `xcodebuild test -scheme Pommora`; package Swift 5.9 vs app Swift 6. Graph: `Document(parsing:)` 8 in-engine sites; `parsedDocument(for:)` 12 callers; styler chain two composition sites; engine has no disk save (surfaces via `@Binding text` + 10 ContextMenu raw writes).

### Keep-Verbatim Register

Runtime-only / OS-bug / library workarounds with verified file:line + reason. Transplant unchanged; do not "simplify."

| Workaround | file:line | Reason |
|---|---|---|
| 149pt height-oscillation guard (frameDidChange observer: width-delta `>0.5` @222 + height-delta `>1` @231; captured `lastObservedViewportWidth` @218) | `NativeTextViewWrapper.swift:218-234` | TextKit2/AppKit frame-change feedback-loop; epsilons tuned to observed behavior |
| `foldedHeadings` stale-binding refresh (re-capture fresh `$foldedHeadings` into coordinator every `updateNSView`) | `NativeTextViewWrapper.swift:319-334` | SwiftUI `@Binding`-staleness; load-bearing for two-way fold sync |
| WritingTools session guard on node switch (`wtStartDocumentId` mismatch discard) | `NativeTextViewWrapper.swift:259-273` | macOS 15+ Writing Tools; discard WT session when file switches mid-session |
| Force full-document layout at init (`ensureLayout(for: documentRange)`) | `NativeTextViewWrapper.swift:201-203` | TextKit2 lazy-layout scroll-drift |
| Content-storage delegate set BEFORE `textView.string` | `NativeTextViewWrapper.swift:154-162,173-174` | Cold-open without flash of expanded folded content |
| `@objc`-selector NotificationCenter observation (not block-based) | `NativeTextViewCoordinator.swift:243-274` | Swift 6 strict-concurrency `Notification` Sendable error |
| `foldedHeadings` as plain `Set<String>` + `onFoldedHeadingsChanged` (replacing stale `@Binding`) | `NativeTextViewCoordinator.swift:30-46` | SwiftUI binding-staleness; documented exact failure |
| `deinit` invalidating `chevronAnimationTimer` | `NativeTextViewCoordinator.swift:308-318` | `Timer.scheduledTimer(target:)` strong-retain leak on page switch |
| `shouldChangeTypingAttributes` base font/style/color force | `+TextDelegate.swift:22-38` | AppKit typing-attr inheritance bleeding heading paragraphStyle into trailing fragment |
| `hasMarkedText` guard in `textDidChange` | `+TextDelegate.swift:56` | IME/dead-key composition corruption |
| WT mode detection + proofread skip + edited-range fallback (`firstEditLen` vs `sel*0.6`) | `+TextDelegate.swift:42-52,89-98,152-155,167` | macOS Writing Tools delivers edits without normal edited-range info |
| `recalcOverscroll` + `clampToInsets` after restyle (guarded to NativeTextView/ClampedScrollView) | `+TextDelegate.swift:156-161` | AppKit scroll-inset/overscroll jitter on height change |
| Mouse/wake-focus-on-link no-preview guard (`NSApp.currentEvent` type) | `+TextDelegate.swift:171-180` | AppKit event-timing; distinguish click-nav from caret-preview |
| `isSyncingHRVisibility` reentry guard | `NativeTextViewCoordinator.swift:90-97` (used in `+HRVisibility`) | AppKit edit-notification re-entry recursion |
| HR `>` marker activation gate (collapse only when followed by space/tab) | `AppleASTSupplementalStyler.swift:137-157` | Prevents "type `>` and line collapses to 1pt" regression |
| HR empty `> ` line `minimumLineHeight` floor (`ceil(body height)`) | `AppleASTSupplementalStyler.swift:83-84` | font-0.1 marker-hiding collapses line to ~1pt |
| HR continuous-bar spacing zeroing (paragraphSpacing/before = 0) | `AppleASTSupplementalStyler.swift:71-72` | Renderer per-fragment bar segments butt-joint seamlessly |
| Table separator-row hiding via source-range arithmetic | `AppleASTSupplementalStyler.swift:217-241` | swift-markdown does NOT expose the `\|---\|` row as a node |
| font-0.1 + clear-color marker collapse (`>` and table `\|`) | `AppleASTSupplementalStyler.swift:148-156,198-213` | Hide glyphs without deleting source (canonical-md preservation) |
| `LineOffsetIndex` UTF-8-byte→UTF-16 column conversion (+ `\n`/`\r`/`\r\n`) | `AppleASTSupplementalStyler.swift:296-378` | cmark-gfm reports UTF-8 byte columns; multibyte breaks without per-scalar walk |
| ThematicBreak emits NOTHING from BOTH stylers (HR owned by `syncHRVisibility`) | `AppleASTSupplementalStyler.swift:248-262` + `MarkdownStyler.swift:179-183` | "Enter is the trigger" UX; emitting fires on every keystroke |
| HR margin-invariant spacing `max(0, 16 - lineHeight/2)`, both caret states; dashes always body-sized, only foregroundColor flips | `+HRVisibility.swift:171-183,256-277` | Eliminates ~11pt vertical jump on caret crossing HR boundary (Session 12 fix) |
| `isInsideCodeBlockParagraph` color-match tolerance 0.03 | `+HRVisibility.swift:230-244` | Mirrors renderer `hasCodeBlockBackground`; survives deviceRGB rounding |
| WT mid-session Cmd+Z recovery (prefer `wtPostUndoSnapshot` over `textView.string`) + undo observer | `+Services.swift:312-340,367-378` | macOS 15 stale accept-action corrupts text + contaminates attrs with 0.1pt marker font |
| WT child-window position fix (capture origin, re-pin >0.5pt drift, 20×0.05s polling) | `+Services.swift:345-363,385-397` | macOS 15 mis-positions the WT Done/Original panel |
| `nudgeAttributes` paragraphStyle re-write to trigger redraw | `+HeadingFolding.swift:123` | TextKit2 `invalidateLayout` alone doesn't re-run imperative `draw(at:in:)` |
| `invalidateFoldLayout` 4-step + fold-start-to-doc-end | `+HeadingFolding.swift:240` | TextKit2 caches Y positions for fragments after the invalidated range |
| `moveSelectionOutOfFoldedRanges` before invalidation | `+HeadingFolding.swift:206` | Layout manager refuses to elide an element containing the active selection |
| `unfocusCaretIfInsideFoldedRange` | `+HeadingFolding.swift:414` | AppKit force-lays-out caret-hosting element, overriding `shouldEnumerate==false` |
| `textParagraphWith` no-op (`return nil`) | `+HeadingFolding.swift:551-556` | Non-empty-range empty-paragraph substitution SIGTRAPs `enumerateTextElementsFromLocation:` |
| `chevronAnimationTick` collect-then-remove (no mutate-during-iterate) + `@objc` selector Timer + `.common` mode | `+HeadingFolding.swift:337-364` | Swift UB froze first animation/page; Swift 6 `@Sendable`; keep ticking during scroll |
| CRLF-safe heading-key strip (`trimmingCharacters(in: .newlines)`) | `MarkdownDetection.swift:263-271` | Swift treats `\r\n` as one grapheme; `hasSuffix("\n")` no-ops on Windows files |
| `isInsideWikilink` manual `[[`/`]]` depth counter (clamp-at-zero) | `MarkdownDetection.swift:375-389` | No token/AST equivalent; sole guard for en-dash transform; tolerates mid-typing unbalanced state |
| Standalone in-isolation parse in `isThematicBreakLine`/`isHeadingLine` | `MarkdownDetection.swift:77,160` | The isolation IS the setext-H2 suppression for `---` |
| CommonMark emphasis flanking + Rule-of-3 stack | `MarkdownTokenizer+Emphasis.swift:51-156` | Hand-tuned to CommonMark; transplant byte-for-byte if kept transitionally before AST swap |
| `isInlineMathContent` currency/math heuristic | `MarkdownTokenizer.swift:210-240` | No Apple-AST equivalent; Pommora-specific money-vs-math discrimination |
| `appendRenderedStandaloneBlock` collapsed-source kern/clear-color geometry | `MarkdownStyler.swift:240-333` | Pixel-precise TextKit2 collapse of multi-char source into image bounds |
| `styleTaskCheckboxes` caret==syntaxEnd edge-case reveal | `MarkdownStyler.swift:540-545` | Boundary caret-reveal tuned to NSTextView selection semantics |
| `shrinkInactiveMarkers` blockCodeTokens filter (`.codeBlock` only) | `MarkdownStyler.swift:408-411` | Inline-`code`-in-heading must still hide `#` markers after caret leaves |
| `taskListRegex` non-empty `[ xX]` requirement (empty `[]` not a checkbox) | `MarkdownStyler.swift:35-45` | Shorthand→GFM canonicalization contract |
| Checkbox-bracket collapse via font 0.1 (NOT zero), brackets kept body-sized | `MarkdownListHandler.swift:296-318` | Checkbox-draw reads `[` pointSize; zero collapses the box |
| Bullet `-` hidden via clear color + kern (NOT font-collapsed) | `MarkdownListHandler.swift:319-334,272-287` | `•` overlay positioning depends on preserved hidden-`-` width + matched headIndent |
| Shift+Enter modifier-flag interception (`NSApp.currentEvent.modifierFlags`) | `MarkdownListHandler.swift:680-687` | macOS maps plain + Shift Return both to `insertNewline:` |
| `performEdit` `isProgrammaticEdit` re-entrancy dance | `MarkdownListHandler.swift:22-25` | NSTextView fires delegate callbacks during programmatic edits |
| `string.contains("`")/("$")` cheap prefilters before `isInside*` | `MarkdownListHandler.swift:380-381,415-416`; `SpellingPolicy:18,25` | Skip AST/token scan on prose; behavior-neutral perf guard |
| `isAutomaticDashSubstitutionEnabled=false` in both construct + live-policy paths | `NativeTextViewWrapper.swift:190` + `+Services.swift:185` | Engine owns em/en-dash; macOS auto-dash double-fires |
| FB22524198 caret Y-snap (KVO on indicator.frame + `isApplyingCaretShift` guard, recursive) | `NativeTextView+CaretWorkarounds.swift:69-106` | Trailing-`\n` caret Y-snap; companion to FB15131180 (height) |
| Block-image caret policy (hide/resize `NSTextInsertionIndicator` over block LaTeX) | `NativeTextView+CaretWorkarounds.swift:19-66` | Caret rendering over inline block images |
| `setMarkedText` paragraph restyle | `NativeTextView.swift:69-78` | AppKit skips `textDidChange` for marked (IME) text |
| `updateTrackingAreas` `.inVisibleRect` create-once | `NativeTextView+HeadingFoldHover.swift:32-43` | AppKit tracking-area lifecycle; auto-tracks visible rect |
| `applyHoveredHeadingKey` `nudgeHeading` invalidation choice (double nudge) | `NativeTextView+HeadingFoldHover.swift:128-145` | `setNeedsDisplay`/`invalidateRenderingAttributes` fail to re-call TextKit2 fragment draw |
| `handleHeadingChevronClick` synchronous fold reconcile + consume-event | `NativeTextView+HeadingFoldHover.swift:190-240` | `shouldEnumerate`-vs-caret race; lags a frame without sync reconcile |
| `performDragBoostTick` autoscroll + `clampToInsets` + movement-threshold | `NativeTextView+DragSelectBoost.swift:41-65` | Drag-selection edge-autoscroll tuned vs NSScrollView |
| `setFrameSize`/`applyManagedFrameSize`/`scrollRangeToVisible` re-entrancy + suppression guards + TK2 end-segment-maxY height pattern | `NativeTextView+FrameAndOverscroll.swift:52-130` | TextKit2 document-height measurement is fragile |
| FB15131180 `@objc(extraLineFragmentAttributes)` bridge + delegate seed + nonisolated/`assumeIsolated` overrides | `MarkdownTextLayoutFragment.swift:720-721,1186-1198,815-816,727-728,128` | Open OS bug; ~30pt usageBounds inflation on trailing heading paragraphs; selector string is KVC contract |
| Per-fragment in-isolation block detection (NOT attribute-based) | `MarkdownTextLayoutFragment.swift:62-70` | Prior `.pommoraThematicBreak` attribute leaked via inheritance ("duplicate HR on every Enter") |
| Pixel-snap math (`backingScaleFactor` floor/ceil) for bar/card/bullet/checkbox | `MarkdownTextLayoutFragment.swift:556-563,385-390,1150-1155` | Sub-pixel seam avoidance; coupled to barWidth/cornerRadius |
| `WikiLinkService.makeStorageState` display→storage normalization + `lastSyncedText` guard before binding write | `+TextDelegate.swift:61-71` | Prevents re-entrant binding churn; stable wikilink IDs across re-renders |
| WikiLink UTF-16 length bookkeeping in `makeDisplayState`/`makeStorageState` | `WikiLinkService.swift:62-101,114-164` | NSRange/NSTextStorage are UTF-16-indexed; multibyte corrupts otherwise |
| WikiLink `(?<!!)` lookbehind (excludes `![[...]]`) | `WikiLinkService.swift:50,52` | Routes image embeds away from wikilink rewrite |
| `applyInlineReplacement` undo/firstResponder/auto-reveal choreography | `+Restyling.swift:279-313` | NSTextView undo/firstResponder interaction (app-inert today; needed when autocomplete wired) |
| `MarkdownPlainText` CodeBlock trailing-newline + BlockMarkup separator | `MarkdownPlainText.swift:31-38,42-47` | swift-markdown leaf-block traversal quirk; word-count fusion (regression-guarded) |
| `Yams.Node.Mapping([])` explicit empty-array init (app I/O) | `AtomicYAMLMarkdown.swift:176` | No nullary init in Yams 5.4.0 |
| `focusBodyEditor` NSView-tree first-responder walk (app) | `PageEditorView.swift:362-378` | AppKit focus-fallback so title rename round-trip completes before focus shifts |

### Open Questions / Decisions Surfaced for Nathan

These need a human ruling; not invented here.

**Scope / API surface**
1. Prune the 8 app-dormant wrapper init params + 4 dormant public selection types during the re-home (shrink to what the app uses), or preserve as forward-looking API for wiki-link/rename/image-paste features not yet wired? Code supports both.
2. Is wikilink autocomplete/rename UI in scope? If yes, bind `isWikiLinkActive`/`pendingInlineReplacement`/`onInlineSelectionChange` in `PageEditorView` + own request/selection state in `PageEditorViewModel`; if no, prune the dead inline-replacement helpers (`displayFragmentAndID`, `caretRangeAfterReplacing`, `applyInlineReplacement`, the `.wikiLinkID` write at `+Restyling.swift:294`).
3. Should the re-homed package update wrapper defaults to match Pommora's real usage (`"SF Pro Text"`/15/`page.id`) or keep generic defaults (`"SF Pro"`/16/`"default"`) since the app always overrides?
4. Does D20 (records 14 params) need a correction entry, or was it deliberately excluding `onLinkClick`? Source is 15.
5. Does the rebuild move the folder `External/MarkdownEngine` → `External/MarkdownPM`, or only rename the SPM product? And is `import MarkdownPM` a blanket rename, or does the product keep `MarkdownEngine` while only the repo rebrands?

**D1 — the central decision (Phase 5)**
6. When a real `WikiLinkResolver` is wired, should resolved ids be **written to disk** as `[[Name|id]]` (Obsidian-incompatible, rename-stable) or kept **OUT of disk** (plain `[[Title]]`, resolution recomputed each load)? There is no guard today — the moment a resolver returns an id, it persists. This must be an explicit ruling, not incidental.
7. What backs the existence resolver — SQLite page/item index, in-memory managers, or a dedicated link resolver? It must be synchronous (called inside the styling hot path).
8. Should the consolidated styler give BlockQuote/Table markers caret-aware reveal (today they collapse unconditionally), or preserve always-collapsed?

**Parse-spine architecture (Phase 3/4)**
9. Should the cached Apple `Document` live on `NativeTextViewCoordinator` (alongside `cachedParsedText`), or should `ParsedDocument` be extended to carry the AST? And who OWNS the unified spine — coordinator or a new `ParseSpine` type?
10. Does `shouldChangeTextIn` (pre-edit) vs `textDidChange` (post-edit) genuinely defeat the size-1 cache per keystroke? Confirm before claiming the regex tokenize runs once.
11. Is `Markdown.Document` Sendable/safe to retain on the `@MainActor` coordinator across events?
12. After P4 moves inline locating to the AST, can `codeTokens`/`latexTokens` etc. be derived from the cached Apple Document — i.e. does the regex tokenizer survive at all, or only its fence/latex/wikilink/imageEmbed subset (Pommora syntax the Apple AST doesn't model)?
13. Should the renderer's per-fragment detection consume the coordinator's cached document/token index instead of parsing isolated substrings, without reintroducing the attribute-inheritance leak or a per-mouseMoved cost regression?

**P4 emphasis/heading specifics**
14. Should the Apple-AST emphasis replacement ADD underscore (`_`) support, or stay asterisk-only to match the deleted parser? (Determines whether P2 tests assert underscore as non-emphasis.)
15. Should emphasis inside inline code/code blocks/LaTeX be suppressed after P4? Current parser does NOT suppress; the AST will.
16. Retain `.italic/.bold/.boldItalic` enum cases (re-emit from AST) or remove them (module-wide exhaustive-switch sweep)?
17. Reconciled single heading rule: CommonMark semantics (space/tab/EOL) matching `isHeadingLine`, or the stricter ` +` styler form? Decides whether tab-indented/bare-`#` lines render as headings.
18. Is the 1-3-letter-run = math rule (`$x$`, `$abc$` render as LaTeX) intentional product behavior or accidental over-trigger?

**Theming / config (P5)**
19. Keep the 16-sub-struct granularity or collapse to fewer grouped structs? And should `MarkdownEditorServices` remain a property of the value-config struct (it's behavior/services, not a value style)?
20. For renderer literals migrating to config (blockquote/divider/bullet), add new sub-structs (BlockquoteStyle, ThematicBreakStyle) + theme color slots, or fold into existing (ListStyle for bullet)?
21. Should code-text color be a `SyntaxHighlighter` responsibility (like `backgroundColor()`) or a `MarkdownEditorTheme` token? (Current asymmetry: background from service, text hardcoded.)
22. Are `ScrollersPolicy`/`SafeAreaInsets`/`DragSelectionPolicy`/`LinkStyle` consumed by the app/TextView coordinators (outside grepped engine Sources)? Need full cross-target trace before any trim.
23. Keep the `InlineLatexStyle` Void-placeholder scaffold, or design inline-LaTeX tuning now?

**Save fan-out / DRY (P6)**
24. Should the unified save helper subsume ContextMenu's 10 raw `self.text` writes (which skip `makeStorageState`+dedup)? Confirm whether those intentionally store display-form text or are a latent bug. And is the full-rebuild path's omission of the spellingState pre-pass intentional or a latent bug (spell-underlines on code/latex until first edit)?
25. Should `performEdit` be refactored to a pure-function core so the 9 transforms become unit-testable without a live NSTextView? Affects P2 test strategy.
26. What is the canonical D5/v2 membership of "the NINE" input transforms? Code supports either bucketing (arrows-as-one vs broken-out; dashes-as-one vs broken-out). FIX the membership explicitly. Also: are bracket-skip-on-Enter and checkbox-shorthand→GFM counted among them?

**Test-run wiring (P2)**
27. Fold the engine's `MarkdownEngineTests` into the app test run (TestableReference/test-plan), or keep as a separate `swift test`? Today it runs by neither under `xcodebuild test -scheme Pommora`. And should `EnterContinuationTests`/`CheckboxCanonicalizationTests` (using `@testable import` against package-internal `MarkdownLists`) move to PommoraTests (would force `public`) or stay in the package?

**Misc**
28. Should the `.wikiLinkID` literal `"NodeLinkID"` (and the four `latex*` keys) be renamed during the re-home, and to what brand-neutral string (must change atomically across all readers/writers, no `Pommora` qualifier)?
29. Confirm the rebuild keeps swift-markdown at a version whose default `ParseOptions` still emit Strikethrough + Table without an explicit flag, or pin an explicit GFM-enabled options value to remove the implicit dependency.
30. Is `foldableHeadings`'s "top-level headings only" restriction (`MarkdownDetection.swift:170-172`) intended to survive, or is nested-heading folding a planned expansion (changes contentRange level-stack logic)?
31. Should `computeActiveTokenIndices` stay in `MarkdownDetection` or move to the coordinator/restyle slice during P6 (it's pure restyle/typing plumbing with 5 coordinator callers)?
32. Is the `NSTextInsertionIndicator` subview-filtering approach (`type(of:) == NSTextInsertionIndicator.self`) expected to survive the targeted macOS version, or should the FB22524198/block-image workarounds be OS-version-gated to drop when Apple ships the fix?
