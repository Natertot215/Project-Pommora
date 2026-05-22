### swift-markdown-engine — vendored

Pommora vendors a subset of [`nodes-app/swift-markdown-engine`](https://github.com/nodes-app/swift-markdown-engine) at `Pommora/Pommora/PageEditor/Engine/`. The upstream is licensed Apache 2.0 (see `LICENSE`). The engine is consumed as source files (not a Swift Package) so Pommora can replace the regex parser + styler with Apple-AST-backed implementations.

#### Upstream commit

- Repository: `https://github.com/nodes-app/swift-markdown-engine`
- Commit SHA: `e683a62` (vendored 2026-05-18)
- Core target only — the `MarkdownEngineCodeBlocks` and `MarkdownEngineLatex` SPM products are NOT vendored. Their no-op defaults in the core `Services/MarkdownEditorServices.swift` are sufficient for v0.2.7. HighlighterSwift + SwiftMath bridges may be added as a later patch.

#### Pommora's modifications to the vendored copy

| Phase | Type | File | Why |
|---|---|---|---|
| 2 (vendor) | DROP | `MarkdownEngine.docc/` | Upstream DocC catalog — Pommora doesn't ship engine docs externally |
| 3 (parser surgery) | DELETE | `Parser/MarkdownTokenizer+Emphasis.swift` | Apple swift-markdown's AST handles `***bold italic***` natively |
| 3 (styler swap) | DELETE | `Styling/MarkdownStyler.swift` + 6 extensions (`+TextStyling`, `+Links`, `+Code`, `+Latex`, `+Images`, `+TaskCheckboxes`) | Pommora-side `PommoraMarkdownStyler` replaces; only 2 call sites |
| 3 (parser surgery) | REIMPLEMENT INTERNALS | `Parser/MarkdownTokenizer.swift` | Type-API preserved (11 non-styling files depend on it); body walks Apple `Document(parsing:)` AST and emits `[MarkdownToken]` shims + supplemental wikilink/image-embed regex scan |
| 3 (parser surgery) | REIMPLEMENT INTERNALS | `Parser/MarkdownDetection.swift` | Type-API preserved; body queries the new Apple-AST-backed `[MarkdownToken]` array |
| 3 (styler swap) | MODIFY CALL SITES | `Styling/TextStylingService.swift` + `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift` | Call `PommoraMarkdownStyler.styleAttributes(...)` instead of the deleted `MarkdownStyler.styleAttributes(...)` |
| 4.5 (auto-pair) | EXTEND | `Input/MarkdownInputHandler.swift` | Adds character-pair auto-pair for `**`/`__`/`[[`/`` ` `` + auto-exit-on-whitespace; doesn't ship in engine |
| v0.2.7.x (code aesthetics) | EXTEND | `Styling/MarkdownStyler.swift` | Adds `.foregroundColor: NSColor.systemRed.withAlphaComponent(0.85)` to the existing `styleCodeBlocks` + `styleInlineCode` attrs dicts so all monospace code text renders in a softened red |
| v0.2.7.x (code aesthetics) | MODIFY | `Services/MarkdownEditorServices.swift` | `PlainTextSyntaxHighlighter.backgroundColor()` returns `NSColor.controlBackgroundColor` (subtle gray semantic system fill) instead of fully transparent |
| v0.2.7.x (bullet glyph) | EXTEND | `Input/MarkdownListHandler.swift` | Inside `applyListMatches`: hide source `-` marker (font 0.1 + clear color) for non-task-list bullets so the renderer can overlay `•`. Only `-` substitutes; `*`, `+`, legacy `•` left literal |
| v0.2.7.x (bullet glyph) | EXTEND | `Parser/MarkdownDetection.swift` | Adds `isDashBulletLine(_:isInsideCodeBlock:)` helper (mirrors `isThematicBreakLine` pattern) — three-stage detection used by the renderer to decide whether to overlay a `•` glyph |
| v0.2.7.x (bullet glyph) | EXTEND | `Renderer/MarkdownTextLayoutFragment.swift` | Adds `hasDashBulletMarker` + `dashBulletMarkerDocumentLocation` + `drawDashBulletGlyph(at:in:)` (always-on, no caret-aware reveal, pixel-aligned via `backingScaleFactor`); extends `renderingSurfaceBounds` to cover the glyph; calls `drawDashBulletGlyph` from `draw(at:in:)` |
| v0.2.7.x (arrows) | EXTEND | `Input/MarkdownListHandler.swift` | Adds `-` to `handleInsertion` fast-path exclusion list; extends the `>` branch with Case A (`←>` → `↔`) + Case B (pasted `<-` then typed `>` → `↔`); new `-` branch for `<-` → `←` |

All retained files keep their original Apache 2.0 license. New Pommora-side files (`PommoraMarkdownStyler`, `PommoraInlineScanner`, `SourceRangeToNSRange`, `MarkersShrinker`, `PommoraWikiLinkResolver`) live at `Pommora/Pommora/PageEditor/Styler/` and `Pommora/Pommora/PageEditor/Services/` (Pommora-licensed; not derivative of engine).
