### MarkdownPM — Pommora-owned (originally vendored from swift-markdown-engine)

MarkdownPM is a Pommora-owned, local Swift Package at `External/MarkdownPM/`, maintained in-tree. It was originally vendored from a subset of [`nodes-app/swift-markdown-engine`](https://github.com/nodes-app/swift-markdown-engine) (upstream licensed Apache 2.0, see `LICENSE`, retained for attribution), so Pommora can replace the regex parser + styler with Apple-AST-backed implementations.

#### Upstream commit

- Repository: `https://github.com/nodes-app/swift-markdown-engine`
- Commit SHA: `e683a62` (vendored 2026-05-18)
- Core target only — the upstream `MarkdownEngineCodeBlocks` and `MarkdownEngineLatex` SPM products are NOT vendored. Their no-op defaults in `Services/MarkdownPMServices.swift` are sufficient for v1; HighlighterSwift + SwiftMath bridges may be added as a later patch.

#### Pommora's modifications (as built)

The as-built MarkdownPM is a re-architecture, not a patch series over the vendored copy. Upstream's hand-rolled regex parser + styler were replaced with Apple-swift-markdown-AST-backed implementations, and the styling / theme / parse surfaces were consolidated into single package-internal types. The table below records the structural changes against the upstream baseline.

| Area | Change | Surface | Why |
|---|---|---|---|
| DocC | DROP | `MarkdownEngine.docc/` | Upstream DocC catalog — Pommora doesn't ship engine docs externally |
| Emphasis parser | DELETE | `Parser/MarkdownTokenizer+Emphasis.swift` (the hand-rolled asterisk/underscore parser) | Deleted entirely — emphasis (`*italic*`, `**bold**`, `***bold italic***`, `_`/`__` forms) is now located on Apple swift-markdown's AST and shimmed into `[MarkdownToken]` by `Parser/MarkdownTokenizer+AppleEmphasis.swift` |
| Tokenizer | REIMPLEMENT INTERNALS | `Parser/MarkdownTokenizer.swift` | Type-API preserved; body walks the Apple `Document(parsing:)` AST and emits `[MarkdownToken]` shims, with a supplemental regex scan only for wikilink / image-embed constructs the AST doesn't model |
| Detection | REIMPLEMENT + UNIFY | `Parser/MarkdownDetection.swift` | Heading / thematic-break / dash-bullet detection unified behind one three-stage (prefilter → AST-confirm) shape; queries the Apple-AST-backed token array; also hosts `FoldedHeading`, `foldableHeadings`, `isInsideWikilink`, and the foldable-heading reconciliation helpers |
| Styler | CONSOLIDATE | `Styling/MarkdownPMStyler.swift` (+ siblings `MarkdownPMStyler+TextStyling` / `+Links` / `+Latex` / `+Images`) | The styling pipeline lives in ONE package-internal `MarkdownPMStyler` enum (the former upstream `MarkdownStyler` and the briefly-planned app-side replacement were both folded in here). Owns the primary per-construct pass; `AppleASTSupplementalStyler` adds the AST-only block constructs (BlockQuote / Strikethrough / Table) last |
| Theme | MERGE | `Configuration/MarkdownPMTheme.swift` | Color + marker theme merged into a single `MarkdownPMTheme` value type carried on `MarkdownPMConfiguration.theme` |
| Services | RENAME | `Services/MarkdownPMServices.swift` | The engine's external-dependency container (`MarkdownPMServices`) — wiki-link resolution, syntax highlighting, LaTeX, embedded images. No-op defaults ship in-package; embedders inject concrete implementations |
| Parse spine | ADD | `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift` (`parsedDocument(for:)`) | One cached parse spine: a single `Document(parsing:)` + `LineOffsetIndex` + `[MarkdownToken]` built once per text and reused by every whole-document consumer (styler, supplemental styler, heading-fold sync), so a restyle triggers exactly one whole-document parse |
| Editor input | EXTEND | `Input/MarkdownInputHandler.swift` + `Input/MarkdownListHandler.swift` | Pommora-specific typing transforms not in the upstream engine: character-pair auto-pair + auto-exit, em-/en-dash auto-format (wikilink-target-aware), `<-`/`->` arrow promotion, and Enter-jumps-the-closer for matched bracket pairs |
| Rendering | EXTEND | `Renderer/MarkdownTextLayoutFragment.swift` | Renderer-drawn surfaces TextKit 2 doesn't supply: dash-bullet `•` glyph overlay, rounded blockquote card + continuous bar, and the foldable-heading chevron |
| Foldable headings | ADD | `TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift`, `TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift`, `Util/HeadingChevronGeometry.swift`, `Util/NSTextLayoutFragment+NSRange.swift` | TextKit 2 paragraph-elision fold via `NSTextContentStorageDelegate`, hover/click chevron with shared hit-test geometry, animated chevron rotation. Fold state round-trips through the embedder as `Set<String>` heading keys |

All retained upstream files keep their original Apache 2.0 license; see `LICENSE`. The Apple swift-markdown GFM AST is pulled as a pinned SPM dependency (see `Package.swift`) and is not vendored into this tree. The styler, theme, services, and parse spine described above are Pommora-authored and package-internal; the public front door the embedder consumes is `MarkdownPMEditor` (a SwiftUI `NSViewRepresentable`) plus `MarkdownPMConfiguration`. NSRange↔SourceRange conversion is centralized in `SourceRangeConverter` (`Styling/AppleASTSupplementalStyler.swift`).
