### Plan: Page editor — Blockquote (active) + Tables (PAUSED)

> **Tables scope PAUSED 2026-05-21** per Nathan's call. The Tables sections below are preserved as reference material — they hold a verified architecture map, stress-test verdicts, and the column-alignment open question — but **no Tables coding starts** until other markdown editor features ship and the engine's behavior is better understood. Reopen the Tables sections only when Nathan says so.

> **Active scope: Blockquote only.** That section is implementation-ready against verified architecture. Estimate ~2h base + ~1.5h iteration buffer per the lessons-applied-budget.

> **This file is a full rewrite.** The prior version (v0.2.7.2 Blockquote + Tables) was written before the dynamic-syntax pattern was discovered. It prescribed implementation methods (custom NSAttributedString attribute keys as render signals; styler emits attributes; column boundaries from natural text layout) that the engine code has since proven wrong — twice (HR Session 12; Lists Session 13). The previous text lives in git history. This rewrite re-derives the architecture from the actual shipped engine code + verified swift-markdown / TextKit 2 APIs, then proposes methods only for the parts that survive the verification step.

> **HR and Lists are shipped.** Page-editor work in this plan is Blockquote (active) and Tables (paused) only. Lists are not in this plan at all (they shipped Session 13 alongside this re-planning gap and never had a planning entry). HR's "Dynamic-syntax pattern" reference lives at `// Features//PageEditor.md`.

> **Code examples are deliberately rare in this plan.** Per Nathan's directive 2026-05-21, no code is described unless the surrounding architecture has been verified against the actual engine code + swift-markdown / TextKit 2 docs. Where the architecture is verified, file:line references replace inline snippets — the engine code is the canonical example.

> **Canonical rules-of-engagement live at `// Guidelines//Markdown.md`.** That document captures the dynamic-syntax pattern, anti-patterns, state mutation rules, lessons L1–L10, and Nathan's locked clarifications. This plan only restates them where the context demands; for the full rule set, read Markdown.md first.

---

#### Status

**Shipped (out of this plan's scope; reference only):**

- HR / divider — `// Features//PageEditor.md → Dynamic-syntax pattern`. The locked architecture for paragraph-level constructs with hide-when-out / reveal-when-in markers.
- Lists rewrite — Session 13 — space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source. `// Features//PageEditor.md` "What v0.2.7.0 ships → Typing helpers" describes the shipped behavior; the architecture lessons are baked into the engine's `MarkdownListHandler.swift`.

**In scope for this plan:**

- Blockquote — fix the current `.backgroundColor` + `headIndent` rendering with a card-chrome target (Apple Calendar event-card reference). Architecture: extend the dynamic-syntax pattern to multi-paragraph constructs.
- Tables — replace the current monospace + faint-bg + hidden-pipes treatment with a real inline grid + cell-editing UI. Architecture: **partly verified, partly blocked** — column alignment is unresolved and must be decided before half the stages can start. See "Tables" section below.

**Out of scope for this plan:**

- Code & quote `Enter}` auto-completion — separate (small) patch
- Code block → red text bug — separate (small) patch
- Auto-format `←` and `↔` (the `<-` / `<->` cases that don't transform on typed input) — separate one-line addition to the arrow transform handler
- Bullet glyph substitution (`-` → `•` visual) — deferred from Session 13 as a known cosmetic caveat

---

#### Lessons that anchor every method below

These were learned by shipping HR (Session 12) and Lists (Session 13). Both shipped after 2–4 hotfix iterations because the prior plan didn't account for the actual engine environment. Every method proposed in this rewrite is tested against them; methods that violate any of these get redesigned rather than wedged.

| # | Lesson | Source | What it forbids |
|---|---|---|---|
| L1 | AST-backed detection > custom NSAttributedString attribute as render signal | HR Session 12; `// Features//PageEditor.md → Dynamic-syntax pattern → Lesson 1` | Storing a Pommora-custom attribute key (`.pommoraBlockquote`, `.pommoraTable`) on a paragraph/source range to drive rendering. AppKit's attribute-inheritance machinery leaks the flag onto newly-typed chars in ways `shouldChangeTypingAttributes` cannot prevent. Engine confirms via the dead-but-reserved `.pommoraThematicBreak` key kept solely for binary compatibility ([MarkdownTextLayoutFragment.swift:21-27](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L21-L27)). |
| L2 | Two detectors MUST share their logic | HR Session 12; `// Features//PageEditor.md → Lesson 2` | Renderer's detection and service's detection drifting. Today they DUPLICATE the same prefilter + AST parse ([MarkdownTextLayoutFragment.swift:69-87](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L69-L87) vs [NativeTextViewCoordinator+HRVisibility.swift:87-107](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L87-L107)) — fragile but works. For Blockquote/Tables, extract into a shared utility OR mirror stages exactly and audit divergence in review. |
| L3 | Service is the sole writer of construct-specific visual attributes; the styler emits nothing for that construct | HR Session 12; `// Features//PageEditor.md → Lesson 3` | `AppleASTSupplementalStyler.visitBlockQuote` writing attributes that the service later writes. A restyle firing while the caret is on the construct undoes the service's work and the user sees attribute flicker. Mirror [AppleASTSupplementalStyler.swift:164-178](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L164-L178) — `visitThematicBreak` emits nothing. |
| L4 | Caret-aware reveal/hide eliminates 3 entire workaround categories | HR Session 12; `// Features//PageEditor.md → Lesson 4` | Cursor-out push handlers, smart-backspace, caret-policy hide-the-indicator. With markers visible while caret is on the line, no invisible content exists for the cursor to fall into. |
| L5 | Don't add safety guards that contradict design intent | HR Session 12; `// Features//PageEditor.md → Lesson 5` | "Setext underline" guards on `---` were added during plan review and contradicted the locked CLAUDE.md statement "Pommora removed Setext H2 support." Before adding any "but what if…" guard, check `CLAUDE.md`, `Framework.md`, `// Features//Pages.md`, and `// Features//PageEditor.md` for an explicit design statement on the case. |
| L6 | Legacy source-mutation expansion and visual-overlay rendering cannot coexist for the same construct | HR Session 12 + Lists Session 13; `// Features//PageEditor.md → Lesson 6` | Adding a CG overlay for HR while the old `MarkdownListHandler` was still expanding `---` into ~100 dashes on Enter. Or adding a CG grid for tables while the styler is still injecting hidden-character attributes that change column widths. Pick one strategy per construct, delete the other. |
| L7 | Real-world testing finds bugs heavy planning misses — budget for 2–4 hotfix iterations after first ship | HR Session 12 + Lists Session 13 | Planned 45min divider took 4h; planned ~6h tables likely 10–15h. Verification gates between stages are mandatory; don't batch-commit a multi-stage feature. |
| L8 | When fixing a problem and trying many things, STRIP and try again — don't pile fixes | HR Session 12 + Lists Session 13; `// Features//PageEditor.md → Lesson 8` | The original HR attempt piled hotfix on hotfix; only restarted after a full revert + replan. The List bullet-glyph substitution attempt was correctly reverted rather than iterated on. When N speculative fixes don't resolve a bug, revert all N and reconsider the design. |
| L9 | macOS default key bindings collapse Shift+Return → `insertNewline:` | List Session 13; `// Features//PageEditor.md → Lesson 3` (List entry) | Hooking `doCommandBy(insertLineBreak:)` to catch Shift+Enter. That selector only fires on Ctrl+\. Detect via `NSApp.currentEvent.modifierFlags.contains(.shift)` inside `shouldChangeText`'s `\n` branch ([MarkdownListHandler.swift:405-412](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L405-L412)). |
| L10 | `shouldChangeTypingAttributes` re-baselines font / paragraphStyle / foregroundColor every keystroke | List Session 13; `// Features//PageEditor.md → Lesson 4` (List entry) | Inheriting tiny/clear attributes from hidden chars to user-typed text is NOT an issue in this engine, because typing attributes are reset by the delegate ([NativeTextViewCoordinator+TextDelegate.swift:22-38](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L22-L38)). Useful for hide-via-attribute patterns; the leak still exists for *Pommora-custom* keys (L1) because the delegate doesn't reset those. |

---

#### Architecture maps

##### swift-markdown — what's actually available

Verified via Context7 against `/swiftlang/swift-markdown` + cross-checked against the engine's existing usage.

| Concept | Verified API | Notes |
|---|---|---|
| Parse | `Document(parsing: source)` → `Document` | Already used in `AppleASTSupplementalStyler` + `NativeTextViewCoordinator+HRVisibility`. |
| Source location | `markup.range: SourceRange?` with `.lowerBound.line` (1-based) + `.lowerBound.column` (1-based) | **UTF-8 vs UTF-16 latent issue.** swift-markdown reports columns 1-based; Pommora's `LineOffsetIndex` treats them as UTF-16 offsets ([AppleASTSupplementalStyler.swift:206-251](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L206-L251)). cmark-gfm's source counts UTF-8 bytes per the spec. ASCII coincides; multi-byte (emoji, accented chars in a table cell, etc.) misaligns. Out of scope to fix here, but Tables ARE the most exposed surface to this. See "Open questions." |
| Mutation | Immutable value types with copy-on-write. Mutate a deep node (`var text = ...; text.string = "..."`); reach the new tree via `text.root`. | New tree shares structure with old via COW. Cheap. |
| Tree rewrite | `MarkupRewriter` protocol — implement `visitXxx(_:)` returning `Markup?`. `nil` deletes; non-nil replaces. `mutating` allowed. | Pattern for table cell-edit + structural add-row/column commits. |
| Canonical emission | `markup.format()` → `String`. For tables, pads cells to align widths in the emitted string (see "Tables — column alignment" below). | Used at commit time, NOT at every render. |
| BlockQuote AST | `BlockQuote` node, `.children` is the sequence of contained `Paragraph` (or other) blocks. `.range` covers the full multi-line span. | Single BlockQuote node represents all consecutive `> ` lines. Two `> foo` lines separated by a blank line are two BlockQuote nodes. |
| Table AST | `Table` node. `.maxColumnCount`, `.columnAlignments: [Table.ColumnAlignment?]`, `.head: Table.Head`, `.body: Table.Body`. `Table.Head/Body/Row/Cell` are explicit node types. `Table.Cell` contains inline children (Text, Emphasis, etc.). | Separator row (`\|---\|---\|`) is NOT a node — it's a syntactic artifact between `head.range.upperBound` and `body.children.first.range.lowerBound`. The engine's current styler already handles this ([AppleASTSupplementalStyler.swift:135-157](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L135-L157)). |
| Table reconstruction | `Table(columnAlignments:header:body:)` constructor. | The only path for `TableStructureRewriter` and `TableCellsRewriter` to emit a modified table. |

##### TextKit 2 — what's actually available

Verified via Context7 against Apple Developer docs + cross-checked against the engine's existing `MarkdownTextLayoutFragment`.

| Concept | Verified API | Notes |
|---|---|---|
| Per-fragment subclass | `NSTextLayoutFragment`. Engine subclass at [MarkdownTextLayoutFragment.swift:40](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L40). Registered via `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` at line 545. | Each fragment owns its draw + bounds + line-fragment array. NOT visible to siblings — no cross-fragment state. |
| Draw entry point | `nonisolated override func draw(at: CGPoint, in: CGContext)` — point is the fragment's draw origin in the parent layout's coordinate system. | Called per-render-pass per-fragment. Cheap operations OK; expensive ones (AST parse) need prefilter (HR pattern: Stage 1 prefilter eliminates ~99% of fragments). |
| Rendering surface | `var renderingSurfaceBounds: CGRect`. Default = `super.renderingSurfaceBounds`. Custom-draw outside that rect gets clipped + invalidation misbehaves. | Must extend per fragment for any custom draw outside the natural frame. HR's extension is ±3.5pt vertical ([MarkdownTextLayoutFragment.swift:178-189](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L178-L189)). |
| Line fragments | `var textLineFragments: [NSTextLineFragment]`. Each has `.typographicBounds`, `.characterRange`, `.glyphOrigin`, `.locationForCharacter(at:)`. | A fragment can hold multiple line fragments (e.g. a wrapped paragraph). Tables: each row is typically one line fragment within its layout fragment. |
| Document-level traversal | `NSTextLayoutManager.enumerateTextLayoutFragments(from:options:using:)` returns the final location. | For document-level operations (e.g. service walking all fragments). Engine doesn't currently use this; service walks via paragraph iteration through textStorage instead. |
| Invalidation | `NSTextLayoutManager.invalidateLayout(for: NSTextRange)`. | The right call for "I changed something and need fragment redraw." Drag-resize would need this if it ever ships. |
| Batched mutation | `NSTextContentManager.performEditingTransaction(_:)`. Engine uses `textStorage.beginEditing/endEditing` (NSTextStorage-level — older AppKit pattern) at [NativeTextViewCoordinator+HRVisibility.swift:51-52](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L51-L52). | For table cell-edit splices, either pattern works; `performEditingTransaction` is the TextKit-2-native form. |

##### Pommora engine — restyle / service / render pipeline

Empirically derived from the shipped engine. Two trigger paths produce attribute writes; one trigger path produces draws.

| Trigger | Calls | What it does | Where |
|---|---|---|---|
| Initial load / full rebuild | `rebuildTextStorageAndStyle` → primary styler + supplemental styler → `syncHRVisibility` | Clears attrs, applies primary + supplemental, then runs the HR service | [+Restyling.swift:17-92](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift#L17-L92) |
| Per-edit | `textDidChange` → `restyleTextView(paragraphCandidates:)` → primary styler + supplemental styler (scoped to candidates) → `syncHRVisibility` (still walks whole doc) | Same pipeline, scoped restyle | [+TextDelegate.swift:40-164](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L40-L164) + [+Restyling.swift:94-129](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift#L94-L129) |
| Per-caret-move | `textViewDidChangeSelection` → (optional restyle if tokens changed) → `syncHRVisibility` | Caret-only changes still re-run the HR service so it can hide/reveal as the caret crosses paragraph boundaries | [+TextDelegate.swift:166-330](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L166-L330) |
| Per-fragment render | TextKit 2's render pipeline → `MarkdownTextLayoutFragment.draw(at:in:)` | Custom draws for code-block bg, LaTeX, ThematicBreak overlay, task checkboxes | [MarkdownTextLayoutFragment.swift:196-215](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L196-L215) |

Service runs AFTER styler in every pipeline. Service writes attributes that the styler didn't (the styler emits NOTHING for the construct). Service is reentry-guarded by a per-construct flag on the coordinator (`isSyncingHRVisibility`) so its own writes don't trigger restyle → recursive call.

`isProgrammaticEdit: Bool` on the coordinator is the canonical guard for programmatic mutations to text storage. Set true around any `replaceCharacters` performed by Pommora code. Set false before returning. The delegate's `shouldChangeTextIn` short-circuits while it's true ([+TextDelegate.swift:335](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L335)).

---

#### Blockquote — ✅ SHIPPED v0.2.7.5 (2026-05-21) with one visual TBD

> **Status:** Always-show overlay implementation shipped per the spec below. **Carries to tomorrow:** horizontal "highlight not extending into syntax gap" visual mismatch — fix paths documented in [`Handoff.md`](../Handoff.md) "Carries to tomorrow" section. Architecture and all other behaviors locked.

---

#### Blockquote — verified spec (REVISED 2026-05-21 — always-show overlay, post-v0.2.7.4 lessons)

##### Pattern lock: always-show, NOT dynamic-syntax

Per Nathan 2026-05-21: blockquote uses the **always-show overlay** pattern (mirrors v0.2.7.4 bullet glyph + task checkbox), NOT the HR-style caret-aware dynamic-syntax pattern. The original plan's "card visible / `>` markers toggle on caret" was abandoned because (a) it produced a text-jump on caret-enter when `headIndent` toggled, and (b) L14 in [`// Guidelines//Markdown.md`](.claude/Guidelines/Markdown.md) — always-show beats caret-aware reveal for non-interactive markers.

The card is permanently visible; `>` markers are permanently hidden via font-0.1 + clear-color. No caret tracking. No service file. No reentry flag.

##### Target visual

- Rounded card (all 4 corners on `.only`; selective on multi-line — see position enum below)
- 3pt vertical accent bar inside card on left
- **Continuous bar across multi-paragraph quotes** — each fragment draws its own segment, butt-jointed via `paragraphSpacing = 0` between quote paragraphs so no seam shows
- Slight right padding via `paragraphStyle.tailIndent` so card stops short of text-area edge
- Same grey color the styler currently emits (just moved into shape-controllable `CGPath`)
- `>` markers hidden; text sits naturally (no `headIndent` shifting content right)
- Nested blockquotes deferred (single-level v1)

Visual values:
- Card fill: same color the styler's current `.backgroundColor` uses (preserved exactly — no color change)
- Card corner radius: ~6pt
- Bar color: `NSColor.separatorColor` raw (Apple pre-attenuates; no `.withAlphaComponent`)
- Bar width: 3pt
- Bar inset from card left: ~4pt
- Bar vertical inset from card top/bottom (only on `.first`/`.last`/`.only`): ~4pt to clear rounded corners
- Right padding (`tailIndent`): ~8pt starting; tune visually

##### Architecture: minimal overlay (2 files touched)

**1. Styler** — `AppleASTSupplementalStyler.visitBlockQuote`:
- **Remove** `.backgroundColor` emission (renderer now draws the fill in a shape that supports corners — same color, different layer)
- **Remove** existing `headIndent` (text sits naturally)
- **Add** `.foregroundColor: NSColor.clear` + `.font: NSFont.systemFont(ofSize: 0.1)` on the `>` marker + trailing space (mirrors task-checkbox marker collapse; L12 — collapse where width is consumed)
- **Add** `paragraphStyle.tailIndent = -8` (negative — pushes right edge inward for the card padding)
- **Add** `paragraphStyle.paragraphSpacing = 0` + `paragraphSpacingBefore = 0` within consecutive `> ` paragraphs so per-fragment bar segments butt-joint seamlessly
- Foreground / italic emphasis / child-walking: untouched

**2. Renderer** — `MarkdownTextLayoutFragment.swift`:
- **Add** `hasBlockquoteMarker: Bool` computed property — three-stage detection mirroring `hasThematicBreak`: (Stage 0) `hasCodeBlockBackground` guard; (Stage 1) trimmed first non-whitespace char equals `>`; (Stage 2) per-fragment `Document(parsing:)` confirms `BlockQuote` child
- **Add** position-within-blockquote enum (`.only` / `.first` / `.middle` / `.last`) — computed by peeking one line up + one line down in textStorage for `>` start; mirrors what other multi-line chrome will need too
- **Add** `drawBlockquoteCard(at:in:)` — `CGPath` with selective corner radii per position, filled with same color the styler used to emit, then 3pt bar drawn inside on left (bar vertical extent inset on `.first`/`.last`/`.only` to clear corners). Mirrors `drawCodeBlockBackground`'s CGPath + fill pattern verbatim.
- **Extend** `renderingSurfaceBounds` to cover the card extent (typically within line-fragment vertical bounds; only minor inflation needed)
- **Call** from `draw(at:in:)` **before** `super.draw` so card+bar render behind text

##### Component file plan

| File | Change |
|---|---|
| [`AppleASTSupplementalStyler.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) | `visitBlockQuote` edits: remove `.backgroundColor`, remove `headIndent`, add `>`-collapse attrs (font 0.1 + clear color), add `tailIndent` for right padding, set `paragraphSpacing = 0` between quote paragraphs. Keep foreground/emphasis/child-walking. |
| [`MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) | Add `hasBlockquoteMarker` + position enum + `drawBlockquoteCard(at:in:)` + `renderingSurfaceBounds` extension. Wire call into `draw(at:in:)` before `super.draw`. |

**Net: 2 files, 0 new files, 0 new services, ~50 lines added, ~3 lines removed/adjusted.**

##### Lesson alignment (L1–L16)

| Lesson | Compliance |
|---|---|
| L1 (no custom render-signal attribute) | ✓ AST detection only |
| L3 (service sole writer / styler emits nothing) | N/A — no service; styler emits structural attrs only (collapse, paragraphStyle), renderer owns the chrome shape |
| L6 (no source mutation) | ✓ |
| L7 (hotfix-iteration budget) | ✓ Smaller scope → 1h + 1h buffer |
| L12 (font-collapse vs clear-color) | ✓ Font-0.1 + clear-color used on `>` (width irrelevant since there's no headIndent), preserves CharacterRange for AST detection |
| L13 (regex drift) | ✓ Single detection site (renderer-only AST) |
| L14 (always-show > caret-aware) | ✓ The pattern lock |
| L16 (existing extension points) | ✓ Mirrors `drawCodeBlockBackground` + `hasThematicBreak` patterns; no new abstractions |

##### Edge cases addressed

1. **Code-block guard** — `> foo` inside ``` ``` ``` doesn't render as blockquote (Stage 0).
2. **Nested blockquotes (`>> deep`)** — render as single-level card in v1. AST detection still triggers on outer `BlockQuote`. Stack-of-bars deferred.
3. **Empty blockquote line (`>` alone)** — AST parses as `BlockQuote { Paragraph {} }` or similar. Card draws around an empty line. Acceptable.
4. **Blank line between quote paragraphs (`> foo\n\n> bar`)** — two separate `BlockQuote` nodes → two separate cards. Standard CommonMark behavior.
5. **`> foo\n> bar` consecutive** — ONE `BlockQuote` with two paragraphs → one continuous card via position enum + `paragraphSpacing = 0`.
6. **Bullet inside blockquote (`> - item`)** — both detectors fire independently; card draws around line, bullet `•` overlays the hidden `-`. Both always-show patterns compose naturally.
7. **Caret on quote line** — no visual change (no caret-aware logic).
8. **Continuous bar across paragraphs** — relies on `paragraphSpacing = 0` between consecutive quote paragraphs to avoid seam gaps; verify in build.

##### Estimate

~1h base + ~1h hotfix iteration buffer (L7). Hotfixes most likely on bar inset values (top/bottom clearance for rounded corners) and right-padding tuning. Single phase, single commit.

---

#### Tables — PAUSED (preserved as reference)

**Status: PAUSED 2026-05-21 per Nathan's call.** Tables scope returns to active only after other markdown editor features ship and we have a better feel for the engine's behavior. The architecture stress-test results below are preserved because the verified architecture + open-question framing is exactly what a future re-start would need.

When Tables work resumes:
- The column-alignment open question (Strategy A / B / C / hybrid) is the central architectural blocker. It must be answered with accumulated engine experience, not from the vacuum the original plan tried to.
- Nathan's locked direction from 2026-05-21 (Section 9.2 of `// Guidelines//Markdown.md`): source on disk stays uniformly padded; column widths live in frontmatter; render layer applies overrides. Implementation cost for inline drag-resize against TextKit's natural-layout constraint is documented in anti-pattern 6.10 of Markdown.md — non-trivial; not a small render-layer feature.
- Stages 3.C (popover editor) and 3.D (structural context menu) are independently viable and could ship first when work resumes. Stages 3.A (inline grid) and 3.B (drag-resize) wait for the alignment-strategy lock.

---

##### Reference (preserved) — Critical open question

**How do columns visually align when the source on disk is not padded?**

The source `| a | b |\n|---|---|\n| longerword | b |` lays out as inline text in TextKit. The current styler hides pipes via font 0.1 + clear color, leaving cell text in place. There is no native column-alignment mechanism in TextKit 2 — `NSTextTable` exists but is rejected (forfeits Writing Tools / Look Up / dynamic-color wins per the Round 4 + Round 5 research preserved in this plan's "Architecture decisions" history).

So the cells of row 1 (`| a |`) sit at one X position; the cells of row 2 (`| longerword |`) sit at a different X. Columns DO NOT visually align unless the source is already padded to equal widths per column.

The prior plan handwaves "column boundary X positions computed from per-row line-fragment text layout." This does not correspond to any actual TextKit API. Three candidate strategies follow, each with tradeoffs:

| Strategy | What it does | Pros | Cons |
|---|---|---|---|
| **A — Padded source canonical form** | On file load + on every save (300ms debounce) + on every table edit commit, run `Markup.format()` on each table. The on-disk source is always padded — `\|Name   \|Count\|Price\|` not `\| Name \| Count \| Price \|`. Natural text layout aligns columns because cell widths are equalized in the source. | Simplest TextKit interaction. Grid alignment "just works." | **Mutates user's source on save.** File-watcher external edits show as unpadded briefly. May normalize away user-intentional formatting (rare but possible). Violates "files canonical (≠ everything is Markdown)" intent for users who care about exact source bytes. |
| **B — Computed-width grid draw + accept text/grid misalignment** | Compute column widths from the AST (max cell text width per column + padding). Draw the grid at those computed widths in `MarkdownTextLayoutFragment.drawTable`. Accept that cell text may not align with grid columns for unpadded source. | No source mutation. | Visible misalignment looks broken — text might cross grid lines or be offset within cells. Most newcomers would read this as a bug. |
| **C — Hybrid: pad on edit commit only** | Source stays as the user typed it. The popover editor's "Done" action runs `Markup.format()` (already in scope for Stage 3.C). Otherwise leave source alone. Inline drag-resize (Stage 3.B) is dropped — drag-resize as designed can't apply custom widths without source mutation. | Less mutation than A. Preserves user typing between edits. | Drag-resize must be cut from this plan. User-typed unpadded tables look slightly off until they pass through the popover. Inline grid still has the alignment problem until first popover edit. |

**Recommendation:** Strategy C, with Strategy A as the second choice if Nathan wants drag-resize to remain in scope. Strategy B's "visible misalignment" outcome doesn't survive Pommora's quality bar.

**Strategy C consequences if locked:**
- Stage 3.A still has the alignment problem for unpadded source. Either accept the misalignment temporarily until first popover edit, OR run `Markup.format()` on each table at file-load (one-shot, not every save) so opened files are always aligned.
- Stage 3.B (drag-resize) is dropped from this plan. Add to "Deferred."
- Stage 3.C and 3.D can proceed largely as the prior plan describes.

**Strategy A consequences if locked:**
- Stage 3.A's alignment problem disappears (source is always padded).
- Stage 3.B is still complex — drag widths must round-trip via the source. Each drag re-pads the source. Possible but high churn.
- File-watcher coordination: external edits unpadding a table get re-padded by Pommora on next save, which may surprise external users.

**Nathan must pick A or C (or describe a D) before Stages 3.A / 3.B start.**

##### Stage 3.A — Inline grid rendering — BLOCKED on column alignment

Once alignment strategy is locked, this stage becomes scopeable. Verified architecture elements:

- **Detection of "this fragment is part of a table"**: per-fragment AST parse, same as HR/Blockquote. Stage 1 prefilter: line starts with `|`. Stage 2: per-fragment `Document(parsing:)` → contains a `Table` child? **NOT a custom `.pommoraTable` attribute** (rejected per L1 — same leak vector as `.pommoraBlockquote`).
- **Header detection**: parse one line backward — does it look like the separator row `\|---\|---\|`? Or position the fragment within the table via AST: the fragment overlapping `table.head.range` is the header.
- **Grid stroke**: per-fragment, after `super.draw`, stroke 1pt `NSColor.separatorColor` for the cell borders this fragment contains. Mirrors the existing `drawThematicBreak` pattern + the more elaborate `drawCodeBlockBackground` CGPath pattern.
- **Header bg fill**: `Color.primary.opacity(0.04)` fill on the header row's line-fragment rect, before the strokes draw.
- **renderingSurfaceBounds**: extend per-fragment for the bordering strokes on the top + bottom edges. Each fragment owns its part; no cross-fragment bounds extension is possible.
- **Per-cell alignment from GFM `columnAlignments`** — the prior plan's claim of "per-cell `paragraphStyle.alignment`" is **wrong**. `paragraphStyle` is per-paragraph, not per-character; a table row is one paragraph with multiple cells. Per-cell alignment cannot be done via paragraphStyle. Options: (1) accept that natural text layout doesn't honor `columnAlignments` and let `Markup.format()` reflect alignment in the padded source via cell-left/cell-right whitespace (the format() output's `|:------|:---:|----:|` separator row encodes alignment, and the padding it applies reflects it); (2) drop alignment honoring entirely from the inline view.
- **`SourceRange → NSRange` for the table range**: uses existing `SourceRangeConverter` + `LineOffsetIndex`. **UTF-16 vs UTF-8 caveat is live for tables** — non-ASCII cell content can mis-locate the splice range, leading to corrupted source on commit. Acceptable for v1 if Pommora's expected content is ASCII-dominant; flag for users who hit it.

##### Stage 3.B — Drag-resize column dividers — SCOPE-AT-RISK

If Strategy C wins the column-alignment question: **drag-resize is dropped from this plan** and added to Deferred. The plan can't ship custom widths without source mutation under Strategy C.

If Strategy A wins: drag-resize is feasible but expensive — every drag commits new padding to source via `Markup.format()`-style re-emit + splice. High churn; needs verification that the editor stays responsive while dragging.

If Strategy A: ~1.5h base + ~1.5h iteration buffer.
If Strategy C: cut entirely; ~0h.

##### Stage 3.C — Double-click popover editor — VERIFIED, INDEPENDENTLY SHIPPABLE

This stage doesn't depend on the column-alignment question — the popover hosts its own SwiftUI Grid which IS column-aligned by SwiftUI layout, regardless of how the inline source looks.

**Verified architecture:**

- **Trigger**: `mouseDown` in coordinator with `clickCount == 2`, inside a fragment that parses as a Table (per Stage 3.A's detection logic — also re-runnable at click time without needing the inline grid to ship first).
- **Anchor**: `NSPopover` anchored to the table's rect, computed via `textLayoutManager.enumerateTextLayoutFragments(...)` over the table's source range. Existing `viewRect(forCharacterRange:using:)` helper at [+InlineSelection / similar coord helpers] handles coord conversion.
- **Host**: `NSHostingView<PommoraTablePopover>` — well-supported pattern, no API uncertainties.
- **Popover content**: SwiftUI `Grid(horizontalSpacing: 0, verticalSpacing: 0)` with `GridRow` per row and editable `TextField` per cell. SwiftUI Grid IS natively column-aligned, so this works regardless of inline-source alignment strategy.
- **Cell styling**: Round 6 recipe from prior plan — `.textFieldStyle(.plain) + .focusEffectDisabled() + .multilineTextAlignment(<from columnAlignments>) + .lineLimit(1...10) + .focused + .onKeyPress(.return / .tab) + .padding (inner) + .frame (outer) + .background (header tint or clear) + .overlay (1pt accent focus border) + .contentShape(Rectangle()) + .onTapGesture + .onHover (NSCursor.iBeam push/pop)`. Each modifier verified against Apple docs in the prior plan + against `// References//focus-patterns.md` for the `.contentShape` + `.onTapGesture` interaction. No code-side changes needed from the prior plan.
- **Commit**: build a new `Table` via `TableCellsRewriter` (MarkupRewriter conforming to the protocol — verified in swift-markdown docs). Emit canonical GFM via `Markup.format()`. Splice into text storage at the table's source range. Wrap in `NSTextContentManager.performEditingTransaction(_:)` (or `textStorage.beginEditing/endEditing` — engine uses the latter elsewhere; either works). Set `isProgrammaticEdit = true` during splice.
- **Source-range capture**: capture the NSRange BEFORE splice. After splice, it's invalid (different length). Let the next restyle re-discover the new table via AST parse.

**Open implementation details to verify at ship time:**

- The `MarkupRewriter`'s `mutating func visitTable(_ table: Table) -> Markup?` returns `Table(columnAlignments:header:body:)` constructed with edited cells. Confirm `Table.Cell(...)` accepts an array of inline children (Text + Emphasis + etc.) — the existing cell content's inline children must be preserved if the edit is just text-content (else markdown formatting inside cells is lost).
- `Markup.format()` output for tables IS padded (verified via Context7 example output). Confirm this is acceptable as the post-edit source under whichever alignment strategy wins.

**Estimate**: ~2h base + ~1.5h iteration buffer.

##### Stage 3.D — Right-click "Add Row / Add Column" context menu — VERIFIED, INDEPENDENTLY SHIPPABLE

Same commit path as 3.C. New `TableStructureRewriter: MarkupRewriter` with an `Operation` enum (`insertRow(at:)` / `insertColumn(at:)`). Returns a new Table with the row/column inserted at the requested index, preserving all existing cells.

**Verified architecture:**

- **Trigger**: extend the existing `ContextMenu.swift` builder. When right-click target is inside a table-containing fragment (detection same as Stages 3.A and 3.C), append four menu items.
- **Click-point → (row, column) hit-test**: row from click Y vs each row fragment's typographic bounds. Column from click X vs computed cell-x boundaries — and **this DEPENDS on the column-alignment strategy**. Strategy A: cell X positions are derived from the padded source's natural layout. Strategy C: cell X positions are derived from `Markup.format()`-equivalent computed widths on the AST (NOT from the inline source's natural layout, which may be misaligned).
- **Rewrite + splice**: same `MarkupRewriter` + `Markup.format()` + `performEditingTransaction` + `isProgrammaticEdit` pattern as 3.C. Doesn't open the popover — structural edits aren't in-cell edits.
- **Frontmatter widths interaction**: row insert preserves column count → widths preserved (if Strategy A). Column insert changes column count → widths reset.

**Estimate**: ~30min base + ~30min iteration buffer.

##### Tables — overall risk inventory

Carries forward from prior plan with one new row:

| # | Risk | State |
|---|---|---|
| 1 | Two-source-of-truth between text storage and viewModel.body | ELIMINATED. Text storage IS canonical. |
| 2 | `NSTextAttachment` view-bounds bug | N/A. No attachments used. |
| 3 | Restyle loop from substitution mutation | N/A. No substitution. Cell-edit commits wrapped in `isProgrammaticEdit + performEditingTransaction`. |
| 4 | `Markup.format()` pipe-padding normalization | Inherent to whichever alignment strategy wins. Documented behavior. |
| 5 | Find/Replace doesn't find cell text | ELIMINATED. Cells live in text storage as `\| cell \|`; system Find works natively. |
| 6 | swift-markdown SourceRange UTF-8 vs Pommora LineOffsetIndex UTF-16 | UNCHANGED — but **tables are the most exposed surface to this**. Cell content with non-ASCII can misalign the splice range and corrupt source on commit. Out of scope to fix; flagged for users who hit it. |
| 7 | `_fixSelectionAfterChangeInCharacterRange` selection drift on programmatic edits | UNCHANGED. Watch during testing. |
| 8 | Column-boundary hit-test cache invalidation | Strategy-dependent. Strategy A: boundaries from text layout, invalidate when restyle fires. Strategy C: boundaries computed from AST, invalidate when AST changes (i.e. on any restyle). |
| 9 | `pommora_table_widths` indexed by `(position, columnCount)` loses widths on reordering | Only relevant if Strategy A keeps drag-resize. Otherwise N/A. |
| 10 | Popover anchoring across page scroll | NSPopover handles view-anchored cases automatically. Verify in build. |
| **11 (NEW)** | **Column-alignment strategy unresolved** | **OPEN.** Blocks Stages 3.A and 3.B. See "Critical open question" above. |

---

#### Open questions

**Blockquote — RESOLVED 2026-05-21.** Nathan-locked: the bar + highlight is a Pommora-side render that does NOT physically exist in the source, mirroring HR's dash-line. Behavior is full HR-pattern dynamic syntax — caret-out shows the visual; caret-in hides the visual and reveals the source `>` markers. Visual chrome is the Round 6 Apple Calendar event-card target (grey rounded card + 3pt vertical bar inside). Documented in `// Guidelines//Markdown.md` Section 9.1.

**Tables — PAUSED 2026-05-21.** All Tables-related questions deferred until scope reopens. The column-alignment strategy (A / B / C / hybrid) remains unresolved and answers come later from accumulated engine experience. Nathan's direction recorded in `// Guidelines//Markdown.md` Section 9.2: source uniformly padded on disk; column widths in frontmatter; render layer applies overrides. Implementation cost vs natural-layout constraint documented in Markdown.md anti-pattern 6.10.

---

#### Deferred / out of scope

- Nested blockquotes (single-level v1; stack via `locations[]` later if real content needs it)
- "Smart inset" bg for first/last lines of multi-line quotes (Down-style)
- Tables drag-resize column dividers (provisionally deferred pending column-alignment strategy lock; possibly dropped entirely under Strategy C)
- Tables remove row / remove column (symmetric to Stage 3.D's add operations; add ships first, remove later)
- `NSTextContentStorage._fixSelectionAfterChangeInCharacterRange` workaround (apply if observed during testing)
- UTF-16/UTF-8 LineOffsetIndex correction for non-ASCII content (latent bug; not triggered by typical Pommora content; out of scope here)
- Cell-level inline markdown rendering inside the inline grid (bold/italic inside cells)
- Per-table UUID in frontmatter instead of `(position, columnCount)` fingerprint (only relevant under Strategy A)
- Fully-inline cell editing (Option B from prior plan — apply if popover-only UX actually bothers user in real use)

---

#### Execution rules

- **Model**: All subagent dispatches use Opus 4.7. Locked override.
- **Branch**: All commits land on `main` directly. Pull fresh main first.
- **Build verification**: `builder` subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1).
- **Format**: `swift format lint --strict --recursive` exit 0 before every commit.
- **Push**: Nathan pushes manually unless explicitly authorized.
- **Docs in commits**: Commit `.claude/Handoff.md` + `.claude/Features/PageEditor.md` updates only on explicit request.
- **Phase commit cadence**: One commit per stage. Each independently green + lint-clean. No multi-stage batch commits (per L7).
- **Stop-and-confirm gate**: Each "open question" must be resolved with Nathan before the stage it blocks starts. Stage 3.C and 3.D may begin without the column-alignment strategy if Nathan locks the "ship 3.C + 3.D first" recommendation.

---

#### Why this rewrite reads cautiously

The prior plan was confident. It prescribed methods that turned out wrong (custom attributes as render signals; per-paragraph `paragraphStyle.alignment` for per-cell alignment; column boundaries from non-existent TextKit APIs) and the implementation cost was paid in HR Session 12 + List Session 13 hotfix iterations. This rewrite is less confident on purpose: every method is named for the file:line that proves it works, every assumption is checked against an Apple-doc or engine-source citation, and the parts that don't survive verification are labeled BLOCKED rather than wedged into the schedule. The cost of confidence in the wrong direction is hours of strip-and-restart; the cost of explicit uncertainty is one Nathan-confirmation cycle per blocked stage.
