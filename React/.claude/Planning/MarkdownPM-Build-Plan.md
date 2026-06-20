# MarkdownPM (React) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Pommora-React's own dynamic-syntax, live-preview Markdown editor — a faithful behavioral port of the Swift `MarkdownPM` package — as the page editor that replaces `Detail/PageView.tsx`.

**Architecture:** Three strata, one owned. A framework-free **behavior layer** (detection, tokens, input transforms, callout codec) is 100% ours and unit-tested without any editor. It sits behind two seams: **CodeMirror 6** as the text substrate and **micromark/mdast** as the GFM parser. All appearance lives in one `Styles.css`, DRY off the root design tokens. The dynamic-syntax pattern (markers reveal when the caret enters a construct, hide/decorate when it leaves) is the single repeated mechanism across every construct.

**Tech Stack:** CodeMirror 6 (`@codemirror/state`, `/view`, `/lang-markdown`), micromark/mdast (`mdast-util-from-markdown` + GFM extension), Vitest, Electron IPC, vanilla-extract token bridge → plain `Styles.css`.

**Spec:** `React/.claude/Planning/MarkdownPM.md` is the authoritative WHAT. This plan is the in-what-order. Section references (§) point at that spec.

## Global Constraints

Every task's requirements implicitly include these (verbatim from the spec):

- **Source == `EditorState.doc` string, always.** No reconstruction layer. Display ≠ source. (§2)
- **Editor binds ONLY to the body.** Frontmatter is stripped on load, held on the page model, re-serialized from the typed object on save — never destroyable through the editor. (§2)
- **Mutations to source are user-initiated only.** No background reformatting; the only editor-initiated writes are keystroke reactions and edit-commits. (§2)
- **Appearance lives in `Styles.css` alone.** The behavior layer never holds a color/size literal — it only assigns class names. Every color/fill/border resolves from root tokens via the `--var` bridge. (§5, §10)
- **Colors authored as hex / tokens, never `rgb()`/`rgba()`** (root React rule).
- **Behavior layer is framework-free.** `parser`, `detect`, `tokens`, `decorations` mapping, `input`, `callouts`, `services`, `constants` import neither CodeMirror nor micromark directly. Only `Styles.css`, `widgets/`, `editor/` are CM6/DOM-aware. (§1, §10)
- **Module root:** `src/renderer/src/MarkdownPM/`. (§10)
- **TDD with a corpus mirroring the Swift `MarkdownPMTests/` suites** (tokenizer, input-transform, styled-range, heading/HR parity). (§10)
- **Catch up to Swift; the only sanctioned go-beyond:** `::` callouts (§11), out-of-the-box tables (§5), native context menu (§8). Everything else ports Swift behavior.
- **Green commit per task.** Adversarial review via standard dispatched agents + a live UIX pass with Nathan before any milestone closeout. (Review-Discipline)

---

## Phase 0 — Prerequisites

Four small, independent gates (spec §1.1). None needs CM6 running. Land these first; they unblock everything.

### Task 0.1: Install CodeMirror 6

**Files:**
- Modify: `React/package.json`

- [ ] **Step 1: Add the deps**

Run: `cd React && npm install @codemirror/state @codemirror/view @codemirror/lang-markdown`
Expected: three `@codemirror/*` entries appear under `dependencies`.

- [ ] **Step 2: Verify the build still typechecks**

Run: `cd React && npm run typecheck`
Expected: PASS (no usages yet; this just confirms the install didn't break resolution).

- [ ] **Step 3: Commit**

```bash
git add React/package.json React/package-lock.json
git commit -m "build(editor): add CodeMirror 6 deps"
```

### Task 0.2: Add explicit parser deps

**Files:**
- Modify: `React/package.json`

- [ ] **Step 1: Add mdast/micromark explicitly** (don't rely on remark-gfm's transitive chain — §1.1)

Run: `cd React && npm install mdast-util-from-markdown mdast-util-gfm micromark-extension-gfm`
Expected: the three packages appear under `dependencies`.

- [ ] **Step 2: Typecheck**

Run: `cd React && npm run typecheck`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add React/package.json React/package-lock.json
git commit -m "build(editor): add explicit mdast/micromark GFM parser deps"
```

### Task 0.3: Wire the `page:updateBody` IPC

**Files:**
- Modify: `React/src/shared/types.ts` (add the request/response contract)
- Modify: `React/src/main/index.ts` (register the handler)
- Modify: `React/src/main/crud/page.ts` (use the existing `updatePageBody`)
- Modify: `React/src/preload/*` (expose `window.nexus.updatePageBody`)
- Test: `React/src/main/crud/page.test.ts`

**Interfaces:**
- Produces: `window.nexus.updatePageBody(relPath: string, body: string): Promise<{ ok: true } | { ok: false; error: string }>` — the renderer's save call. Reuses `updatePageBody` in `crud/page.ts`, which already reconstructs the file via `writePageFile` (frontmatter-preserving) + atomic write.

- [ ] **Step 1: Write the failing test** — body write preserves frontmatter

```ts
// page.test.ts
test('updatePageBody rewrites body, preserves frontmatter + foreign keys', async () => {
  const root = await makeTempNexus({ 'A/p.md': '---\nicon: star\nfoo: bar\n---\nold body' })
  await updatePageBody(root, 'A/p.md', 'new body')
  const out = await readFile(join(root, 'A/p.md'), 'utf8')
  expect(out).toContain('new body')
  expect(out).toContain('icon: star')
  expect(out).toContain('foo: bar')   // foreign key preserved
})
```

- [ ] **Step 2: Run it, expect FAIL** — `Run: cd React && npx vitest run src/main/crud/page.test.ts` → FAIL (handler/signature missing or not exported).

- [ ] **Step 3: Implement** — add the IPC contract to `shared/types.ts`, register `ipcMain.handle('page:updateBody', …)` in `main/index.ts` delegating to `updatePageBody`, expose it in preload. Return the `{ ok }` envelope (never throw across the boundary — global rule).

- [ ] **Step 4: Run it, expect PASS.** `Run: cd React && npx vitest run src/main/crud/page.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add React/src/shared/types.ts React/src/main React/src/preload
git commit -m "feat(editor): add page:updateBody IPC for body writes"
```

### Task 0.4: Add the missing color tokens

**Files:**
- Modify: `React/src/renderer/src/design-system/tokens/color.css.ts`
- Modify: `React/src/renderer/src/design-system/tokens/theme-vars.css.ts` (export the new `--var`s through the bridge)

**Interfaces:**
- Produces: CSS vars `--system-accent` (NEW — OS accent, standing var), `--color-link` (= `var(--system-accent)`), `--color-connection` (= `var(--accent)`, Pommora accent), `--color-code`, and an explicit `--accent` binding — consumed by `Styles.css` + global `styles.css` (§1.1, §5).

- [ ] **Step 1: Add the system-accent var** — add `--system-accent` to `theme-vars.css.ts` (seed with `DEFAULT_ACCENT`), and populate it on load/refresh (alongside `applyAccent`) from `window.nexus.systemAccent()` (Electron) / `readCssAccentColor()` (web) — the OS-accent read already exists; today it only feeds `--accent` when the setting is `system`.
- [ ] **Step 2: Add the link/connection/code tokens** — as named semantic color options alongside the `label`/`fill`/`separator` families (labels side, NOT the tint system): `link` = `var(--system-accent)` (external links), `connection` = `var(--accent)` (Pommora accent), `code` = systemRed @ 0.85 (authored as `#…AA` hex per the no-rgba rule). Heading-marker gray reuses the existing `label.tertiary`.

- [ ] **Step 3: Verify the bridge exports them** — grep `theme-vars.css.ts` for `--system-accent`, `--color-link`, `--color-connection`, `--color-code`.

Run: `cd React && grep -E "color-link|color-code|accent" src/renderer/src/design-system/tokens/theme-vars.css.ts`
Expected: all three present.

- [ ] **Step 4: Typecheck + build the tokens**

Run: `cd React && npm run typecheck`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add React/src/renderer/src/design-system
git commit -m "feat(tokens): add system-accent + link/connection/code tokens for the editor"
```

### Task 0.5: Heading-fold store (`.nexus/folds.json`)

Heading-fold state in its **own dedicated file** — out of frontmatter, out of the index (spec §2). Per-machine, sync-excluded. Its own JSON (not a shared `workspace.json`) so the per-page map can't bloat an unrelated store; future per-page UI-state concerns each get their own file the same way.

**Files:**
- Create: `React/src/main/io/folds.ts` (read/write `.nexus/folds.json`)
- Modify: `React/src/shared/types.ts` (the `folds:get` / `folds:set` contract)
- Modify: `React/src/main/index.ts` (register handlers); `React/src/preload/*` (expose `window.nexus.folds`)
- Modify: the sync-exclusion list so `folds.json` never syncs (mirror Obsidian)
- Test: `React/src/main/io/folds.test.ts`

**Interfaces:**
- Produces: `window.nexus.folds.get(): Promise<FoldState>` and `window.nexus.folds.set(pageId, keys): Promise<{ ok }>`. `FoldState = Record<entityId, string[]>` (page id → ordinal-disambiguated fold keys). Consumed by the editor's fold persistence (Task 3.5).

- [ ] **Step 1: Write the failing test** — set/get round-trips fold keys for a page id, and a missing file reads as empty state.

```ts
test('fold store round-trips folded headings by id, empty when absent', async () => {
  const root = await makeTempNexus({})
  expect(await readFolds(root)).toEqual({})
  await writeFolds(root, 'page-1', ['## Notes'])
  expect((await readFolds(root))['page-1']).toEqual(['## Notes'])
})
```

- [ ] **Step 2: Run, expect FAIL** — `Run: cd React && npx vitest run src/main/io/folds.test.ts`.
- [ ] **Step 3: Implement** `folds.ts` (atomic write, lenient read → empty on absent/corrupt), the IPC handlers, preload exposure, and add `folds.json` to the sync-exclusion list.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(editor): local .nexus/folds.json heading-fold store`.

---

## Phase 1 — Framework-free behavior layer (no CM6)

The de-riskable core. Pure functions over `(text, offsets, ast)` → `(tokens, decorations-intent, transforms)`. **100% unit-tested with Vitest; CM6 is not imported here.** Build the test corpus in lockstep, mirroring the Swift `MarkdownPMTests/` suites. This is where most TDD value lives.

**File structure created in this phase** (`src/renderer/src/MarkdownPM/`):
- `parser/index.ts` — the parser seam: `parse(text) → Ast`, `confirmLine(line) → BlockKind | null`, helpers `isInsideCode/isInsideWikilink/isInsideLatex(offset, text)`.
- `tokens/index.ts` — `Token` model (`kind`, `range`, `contentRange`, `markerRanges`) + `tokenize(text, ast) → Token[]` + `activeTokenIndices(tokens, selection) → Set<number>`.
- `detect/*.ts` — one helper per construct (regexes verbatim from spec §4), shared by render + active logic.
- `input/*.ts` — pure transforms: given `(doc, selection, key)` return `{ changes, newSelection } | null`.
- `callouts/codec.ts` — `::` ⇄ `> [!type]` transform + detection of the canonical form.
- `constants.ts` — non-CSS numbers (nesting cap 3, debounce ms…).

### Task 1.1: Parser seam — `parse` + helper queries

**Files:**
- Create: `src/renderer/src/MarkdownPM/parser/index.ts`
- Test: `src/renderer/src/MarkdownPM/parser/parser.test.ts`

**Interfaces:**
- Produces: `parse(text: string): MdastRoot` (wraps `fromMarkdown` with the GFM extension); `isInsideCode(offset, text): boolean`, `isInsideWikilink(offset, text): boolean`, `isInsideLatex(offset, text): boolean` (line-scoped scans, no AST). Consumed by `detect/*` and `input/*`.

- [ ] **Step 1: Write failing tests** — `parse('# Hi').children[0].type === 'heading'`; `isInsideWikilink(3, '[[ab]] x') === true` and `=== false` at offset 7; `isInsideCode` true inside a fenced block.
- [ ] **Step 2: Run, expect FAIL** — `Run: cd React && npx vitest run src/renderer/src/MarkdownPM/parser/parser.test.ts`.
- [ ] **Step 3: Implement** — `parse` via `fromMarkdown(text, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] })`; the three helpers as line-scoped offset scans (the `[[`/`]]` depth counter for wikilink, etc., per §4.1/§4.6).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(MarkdownPM): parser seam + inside-code/wikilink/latex helpers`.

### Task 1.2: Detection rules (regex + AST), one helper per construct

**Files:** `detect/inline.ts`, `detect/blocks.ts`, `detect/lists.ts` + `detect/detect.test.ts` (corpus).

**Interfaces:**
- Produces: per-construct detectors returning ranges — `headings`, `thematicBreaks`, `blockquotes`, `dashBullets`, `taskCheckboxes`, `tables`, the inline regex matchers (code/latex/image/link), and the three-stage block confirmers. All regexes copied **verbatim** from spec §4.1 — **except wikilinks: import `pageLinkPattern` + `normalizeTitle` from `@shared/connections`** (the canonical project regex — DRY with the scanner/resolver; do NOT port a Swift `[[Name|alias]]` duplicate). React's connection model is title-only.

- [ ] **Step 1: Write the corpus tests** — assert each verbatim regex matches/rejects the exact edge cases the spec calls out (e.g. bare `-[]` matches as a *list line* but NOT as a checkbox; `---` always HR, no setext; heading needs `[ ]{0,3}` not a tab). Mirror `HeadingDetectorCorpusTests` / `StyledRangeCorpusTests`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the detectors with the verbatim patterns + the three-stage block confirm (code-guard → cheap prefilter → per-line AST confirm).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(MarkdownPM): construct detection (verbatim regex + AST confirm)`.

### Task 1.3: Token model + emphasis tokens + active-token computation

**Files:** `tokens/index.ts`, `tokens/emphasis.ts` + `tokens/tokens.test.ts`.

**Interfaces:**
- Produces: `tokenize(text, ast): Token[]` and `activeTokenIndices(tokens, selection): Set<number>`. Token = `{ kind, range, contentRange, markerRanges }`.

- [ ] **Step 1: Write tests** — the emphasis collapse rules (`***x***` → one bold-italic; `**a *b* c**` → bold + nested italic) and the active-token rules (caret at `end` excludes wikilink; selection over latex forces active) from §4.3 / §5-active.
- [ ] **Step 2: FAIL.** **Step 3: Implement** the AST emphasis walk + marker-geometry reconstruction (re-validate offsets against mdast — §4.3) + active computation. **Step 4: PASS.** **Step 5: Commit** — `feat(MarkdownPM): token model + emphasis + active-token computation`.

### Task 1.4: Input transforms (pure)

**Files:** `input/lists.ts`, `input/pairs.ts`, `input/dashArrow.ts`, `input/smartBackspace.ts`, `input/checkbox.ts` + `input/input.test.ts` (corpus mirroring `InputTransformCorpusTests`).

**Interfaces:**
- Produces: each transform `(doc: string, sel: Range, inserted: string): { changes, newSelection } | null`. Pure — no CM6. Covers list continuation, checkbox canonicalization, auto-pair + auto-delete, bracket-skip, dash/arrow, smart-backspace (all line markers — §6.9), Enter vs Shift+Enter.

- [ ] **Step 1: Write the corpus** — one assertion per spec §6 rule (e.g. `-[]` + space → `- [ ] ` caret after; empty-item Enter makes another empty item; `--`+nonDash → `—`; smart-backspace at content-start of `- [ ] x` deletes the whole marker → `x` at col 0). **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** — `feat(MarkdownPM): pure input transforms + corpus`.

### Task 1.5: Callout codec (`::` ⇄ `> [!type]`)

**Files:** `callouts/codec.ts` + `callouts/codec.test.ts`.

**Interfaces:**
- Produces: `expandShorthand(line): string | null` (`::` → `> [!note]`), `isCalloutBlock(node): boolean`, `calloutType(node): string`. Detection consumes the canonical `> [!type]` form, never the `::` shorthand (§11 swappability).

- [ ] **Step 1: Tests** — `::` at line start → `> [!note] `; existing `> [!warning]` detected with type `warning`; round-trip stable. **Step 2: FAIL. Step 3: Implement** (isolated codec — the only place the on-disk format lives). **Step 4: PASS. Step 5: Commit** — `feat(MarkdownPM): callout :: ⇄ > [!type] codec`.

### Task 1.6: Decoration-intent mapping (still framework-free)

**Files:** `decorations/intent.ts` + `decorations/intent.test.ts`.

**Interfaces:**
- Produces: `decorationsFor(tokens, active, text): DecoIntent[]` where `DecoIntent = { from, to, kind: 'class' | 'widget' | 'hide', className?, widget? }`. This is the bridge the `editor/` adapter consumes — pure data, no CM6 types. The class names are the contract with `Styles.css`.

- [ ] **Step 1: Tests** — an inactive bold token yields `hide` intents on its markers + a `class: md-bold` on content; an HR yields a `widget: hr` when inactive, nothing when active. **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** — `feat(MarkdownPM): decoration-intent mapping`.

**Phase 1 exit gate:** the entire behavior layer is green under Vitest with the corpus, zero CM6 imported. Dispatch an adversarial review (standard agent) over the corpus vs spec §4/§5/§6 before moving on.

---

## Phase 2 — CM6 wiring + `Styles.css` + first pixels

Stand up the editor surface and prove the decoration pipeline end-to-end on the two simplest constructs.

**Files created:**
- `MarkdownPM/index.ts` — the `<MarkdownEditor body onChange>` React component.
- `MarkdownPM/editor/view.ts` — builds the `EditorView`, the decoration `ViewPlugin` that reads `decorationsFor(...)` and converts `DecoIntent` → CM6 `Decoration`, and the selection→active recompute.
- `MarkdownPM/Styles.css` — the single stylesheet; start with `.md-bold`, `.md-italic`, `.md-h1…h6`, `.md-hidden` (zero-width marker hide), all reading `--var` tokens.
- Modify: `Detail/PageView.tsx` — mount `<MarkdownEditor>` on the loaded page body.

**Task ladder (each = detect-already-done → map → CM6 convert → Styles.css → live-verify):**
- **2.1** `editor/view.ts`: mount CM6 on a body string, dispatch `onChange` with `doc.toString()`. Verify the placeholder is replaced by an editable plain-text surface (Nathan live-checks text edits + that saves round-trip via Task 0.3).
- **2.2** The decoration `ViewPlugin`: on every doc/selection change, run `parse → tokenize → activeTokenIndices → decorationsFor` and convert intents to a `DecorationSet` (`class` → `Decoration.mark`, `hide` → zero-width `Decoration.replace`). Wire `Styles.css`.
- **2.3** Render **bold/italic/headings** read-with-reveal: markers hide caret-out, show caret-in; heading sizes from the §5 scale in `Styles.css`. **Live UIX check with Nathan.**

**Phase 2 exit:** typing in a real page shows live bold/italic/heading styling with caret-aware markers, saving to disk. The pipeline is proven; remaining constructs are repetition of one shape.

---

## Phase 3 — Constructs (ordered task ladder)

**The repeated task shape** (apply per construct; each is one green commit + a live check):
1. Decoration intent already emitted by Phase 1 `decorationsFor` (extend if needed, with a test).
2. Add the construct's classes/widget to `Styles.css` (colors via `--var`).
3. Build its `widgets/` component if it needs DOM (HR line, blockquote box, bullet, checkbox, code-copy, fold-chevron, image, latex).
4. Wire caret-aware reveal or always-show per the spec's per-construct locking.
5. **Live UIX verify with Nathan.**

**Order (simplest → hardest):**
- **3.1 Strikethrough + inline code** — marks only; inline code uses the shared `code` style block (§5 "Code — its own styling identity").
- **3.2 Fenced code blocks** — the `code` style block as a full-width block; the **code-copy widget** (top-right, §5).
- **3.3 Lists + bullet glyph** — `•` always-show overlay at 1.5× body; `-` only.
- **3.4 Task checkboxes** — **reuse the `chipCheckbox` component**; checked = nexus `--accent`; click toggles `[ ]`↔`[x]` (§5).
- **3.5 Headings — foldable** — the fold chevron (Lucide `chevron-right`, sidebar `.twisty`), **hover-only when open, persistent in gutter when closed** (§5); collapse via the sidebar `Reveal` grid animation (180ms ease); fold state read/written through the **`.nexus/folds.json`** store (Task 0.5), keyed by page id, **not frontmatter** (§2).
- **3.6 Blockquote** — always-show card + bar widget; colors in `Styles.css` from root tokens (§5).
- **3.7 Thematic break (HR)** — caret-aware line widget.
- **3.8 Tables — out-of-the-box** — styled (monospace, faint fill) with pipes + separator hidden caret-out, inline text editing (§5). No grid engine.
- **3.9 Markdown links + wikilinks** — colored inline text, never chips. **Wikilinks wire to the existing connections layer** (§7): move `buildLinkIndex` to `@shared/`, build the `LinkIndex` renderer-side from the loaded page tree, resolve via `resolveTitle` → three states (resolved / phantom / ambiguous); re-derive on tree change. Click-routing navigates to `targetId`; rename-cascade rides the existing `main/connections/rewrite.ts` + `crud/cascade.ts`. (Backlinks panel = separate UI, out of scope.)
- **3.10 Image embeds + LaTeX** — widget render via the image/latex service seams (no-op defaults show source).
- **3.11 Callouts** — the `::` codec from Task 1.5 wired to an always-show box widget; **separators inside bound to the box, not the page gutters** (§11); blockquote-model continuation.

Each task expands into the bite-sized TDD shape (decoration-intent test + a live visual check) when picked up.

---

## Phase 4 — Typing helpers wired into CM6

Wire the Phase 1 pure transforms into the CM6 keymap (the transforms are already tested; this is the adapter + atomic-transaction + re-entry guard).

- **4.1** A keymap that routes Enter/Shift+Enter/Tab/Backspace/`[`/`(`/`` ` ``/`-`/`>`/space through the matching `input/*` transform, applying the result as one transaction (the `isProgrammaticEdit`-analog re-entry guard — §6 intro).
- **4.2** List continuation + smart-backspace (all markers) live.
- **4.3** Auto-pair + bracket-skip + checkbox canonicalization live.
- **4.4** Dash/arrow auto-format live.
- **4.5 Connection autocomplete panel (`[[`)** — port the Swift `AutoCompleteWindow` design (§12): typing `[[` opens a glass popup above the caret; pure presentation over `{id,icon,title}[]` + `query` + `onSelect`/`onCancel`. Unit-test the `highlightSplit` prefix helper; candidates filter the loaded page tree (the §7 connections source); selecting inserts the title. Reuse `GlassSurface` + chip-density rows; ↑/↓/Enter/Esc keyboard nav.
- **Live UIX check** after each.

---

## Phase 5 — Editor shell

- **5.1 Title + divider + scroll layout** — 28px bold title, 14px gap, 1px inset divider, 90px scroll-tracking top zone, 24px body inset (§8). Title Enter → focus body + rename.
- **5.2 Save pipeline** — debounce → `page:updateBody` (Task 0.3) → flush-on-context-loss (page-switch, blur, close); pending-error alert (§8).
- **5.3 Native context menu** — main-process `Menu.buildFromTemplate` + `popup({ frame: focusedFrame })`; standard items + Format/Heading/Lists/Block submenus with checkmark state computed from CM `EditorState` and passed to the template build; actions dispatch back via IPC (§8). Build-time test: verify Writing Tools Rewrite-replace against the live surface; accept display-only if it fails.
- **5.4 Stats footer** — hover-revealed line/word/char counts (§8).

---

## Phase 6 — Post-functional UIX pass (mandatory)

Per Review-Discipline: after the editor functionally works and is green, a UIX review of the *actual working UI* runs with Nathan before closeout — spacing, reveal feel, animation parity, color matching (incl. the optional closed-heading `label.secondary` tint), checkbox/chevron fidelity. Fold findings, re-verify, then close the milestone.

---

## Self-Review (against the spec)

- **Coverage:** every spec section maps to a task — §2 source-of-truth (Global Constraints + 2.1/5.2), §3 dynamic-syntax (Phase 2 pipeline), §4 detection (1.1–1.3), §5 constructs (Phase 3, all bullets), §6 typing helpers (1.4 + Phase 4), §7 service seams (wikilink resolver wired to the existing connections layer in 3.9; image/latex/syntax no-op in 3.10), §8 shell + menu (Phase 5), §9 deferred (table engine intentionally absent), §10 module shape (Phase 1 file structure), §11 callouts (1.5 + 3.11), §12 connection autocomplete (4.5). No gaps.
- **Sequencing sanity:** behavior layer (Phase 1) is fully testable before CM6 exists, so the highest-value de-risking happens first; CM6 wiring (Phase 2) proves the pipeline on two constructs before the Phase 3 repetition; the table engine's hard parts are absent by design.
- **Re-plan rule:** Phases 3–5 are a task ladder, not frozen steps — re-assess each against what the prior green commit surfaced (Studio hard rule). Expand each into bite-sized TDD steps at pickup time.
