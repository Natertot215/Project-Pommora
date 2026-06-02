## MarkdownPM — Decision Surface

### Locked Rulings (2026-06-02)

Nathan's decisions on the surface below. Scope revisions noted; these supersede the per-decision options where they conflict.

- **D1 Wikilinks on disk — BLESSED.** Keep plain `[[Title]]` on disk; resolve/search by ID internally; Obsidian-compatible. Do **not** write `[[Title|<id>]]` to disk in this rebuild.
- **D2 Duplicate-title resolution — ID-based**, scoped by collection + vault (the Wiki-Link spec already specs the scoping; it just isn't *displayed*). No auto-binding a bare-typed title to a guessed page.
- **D3 Reserved chars (`|` `]`) — accepted + documented but NOT hard-locked.** Nathan has bypassed this in Obsidian, so don't forbid these in titles; tolerate + test the failure shape, leave the door open.
- **D5 Auto-transforms — all 9 ratified** (incl. the byte-changing `--`→`—` and spaced `-`→`–`).
- **D7 Emphasis — sign-off granted.** Delete the hand-written emphasis parser; accept Apple's emphasis as the new truth. The guarantee is **"tested-identical on a fixed corpus, every intentional divergence flagged + scoped,"** not "byte-identical."
- **D8 / Items — SCOPE CUT.** Items are **EXCLUDED** from this rebuild. No Item rendering profile; no `@`-item-tagging (a separate future feature, triggered via `@` per the earlier brainstorm — do **not** build it). **Wikilinking is scoped to Pages only.** Keep the styler clean enough not to *preclude* a future Item profile, but build nothing Item-specific. (Mutes D9 → one Pages value set.)
- **D12 Merge / parallel — no active parallel session.** The parallel-looking working-tree changes are stale/background; committed 2026-06-02. `graphify-out/` gitignored (55MB regeneratable).
- **D13 #9 fix — NO standalone.** The per-caret glitch is not a separate phase/release; it is fixed *naturally* by the parse-consolidation. Removed as a standalone step.
- **Testing mandate — TIGHT.** Nothing slips through the cracks: every formatting edge-case, lost function, and behavior change must be **flagged and scoped** (a divergence ledger). No silent drops.
- **Wikilinks = SEPARATE post-rebuild session.** Do **not** build wikilinks during this rebuild — the engine must be rebuilt first. This rebuild only **preserves the groundwork** (the engine's display/input adapter + the resolver-protocol seam, kept dormant). Build nothing beyond the most foundational concrete needed to keep that seam intact.

Reversible decisions (D11, D14–D25): my recommended defaults stand pending Nathan's blanket confirm or per-ID flags.

---


> Generated from the decision-surface sweep (6 agents). Every open decision for the MarkdownPM rebuild, ordered by stakes. Rulings get recorded inline (**RULED:**) as Nathan locks them. Reversible ones carry my recommended default — accept unless flagged.

**26 decisions** — The decision surface is 26 real decisions, and the stakes concentrate heavily at the front: four on-disk-locked decisions (all clustered around the wikilink id format, duplicate-title resolution, reserved-character titles, and the heading-fold-key format) plus six hard-to-reverse ones (the byte-changing dash transforms, line-ending normalization, the byte-identical-vs-Apple-parser contradiction, the speculative Item profile, the styler-merge sequencing, and the package-safety-settings choice) are where a wrong call is expensive or permanent. The remaining sixteen are reversible module-naming, styling-consolidation, parser-cleanup, and process choices — most with a clear low-risk recommendation — but the whole surface rests on a single reframing the plan currently gets wrong: Phase 3 ACTIVATES a brand-new on-disk wikilink format for the first time rather than preserving an existing one, so it deserves its own paradigm-decision rather than sliding in as a refactor step.

### On-Disk-Locked — permanent once users have files (decide carefully)

#### D1 · On-Disk — Right now Pommora never writes a hidden permanent code into your wikilinks — it saves them as plain [[Title]]. The plan would 'activate the resolver,' and the underlying code is already wired to write [[Title|<hidden-id>]] when it has an id. Do we START writing that hidden-id format into users' files as part of this rebuild, or keep links plain and decide the on-disk format as its own separate, deliberate decision?
*Why it matters:* The moment Pommora writes [[Title|<id>]] into a saved file, that format lives in users' files forever and is expensive to change later; getting the separator or id style wrong after hundreds of links exist means rewriting everyone's files.

- **A.** Keep plain [[Title]] through this rebuild; wire a resolver that drives live/muted rendering and click navigation but does NOT write the id to disk yet (the safe activation)
- **B.** Activate the resolver AND lock the [[Title|<id>]] on-disk format now, delivering rename-safety but committing the format under real user data
- **C.** Keep the id association only in Pommora's own index (SQLite), never in the file — files stay maximally clean, identity is Pommora-side

**▶ Recommendation:** Option 1. Wire the resolver so links resolve and navigate, but do NOT start writing |<id> into files until the exact id format is ratified through your paradigm-decision protocol as its own focused decision. The plan's Phase-2 test would otherwise be freezing a format that has zero real-world data behind it — cementing an unproven on-disk contract mid-refactor.
  ◦ *Plain English:* 'Resolver' = the code that answers 'does this linked page exist, and which one is it.' 'On-disk format / serialization' = the exact characters written into the saved .md file. 'ULID' = the kind of permanent random id code Pommora already uses. The trap: once links exist in saved files in one format, changing the format means rewriting everyone's files.

#### D2 · On-Disk — When two pages share the same title in different folders (which Pommora allows), how should the editor's resolver decide which page a [[link]] points to — and should the editor be allowed to auto-assign an id to a link the moment you type it?
*Why it matters:* The editor's resolver only receives the visible title text and a character position, not which folder the link lives in, so a link to [[Notes]] could silently bind to the wrong Notes page — and if that wrong id then gets written to disk, a UI-feeling bug becomes a permanent wrong-link in the file.

- **A.** Resolver picks deterministically by title alone (e.g. first/oldest match); accept that duplicate-title links may bind to the 'wrong' page until disambiguated
- **B.** Extend the resolver call so Pommora knows the source page's folder, enabling the spec's 'prefer a match in the link's own container' rule
- **C.** Only ever assign/persist an id when the user explicitly picks a target from an autocomplete picker; bare-typed [[Title]] stays id-less and resolves loosely at render time

**▶ Recommendation:** Option 3 for this rebuild — only stamp an id on explicit user intent (future autocomplete picker), never auto-bind a bare-typed title to a possibly-wrong page. Container-aware resolution (option 2) is the right long-term answer but it's a Pommora-side resolver design decision, not something to settle inside an engine-consolidation pass.
  ◦ *Plain English:* 'Display name' = the title text you see between the brackets. 'Bind / resolve' = deciding which actual page a link points at. 'Autocomplete picker' = the dropdown of existing pages you'd choose from when typing a link.

#### D3 · On-Disk — The wikilink format reserves the characters | and ] for its own structure, so a page titled 'Q3 | Review' or 'Notes [draft]' can't be safely linked. Since 'filename = title' lets a title be almost any text, do we accept this limit and document it, add escaping, or restrict what characters a title can contain?
*Why it matters:* A link to a page whose title contains | or ] would parse ambiguously and could silently lose its hidden id on the next save — and once it's writing to disk under real data, that's a data-loss bug rather than a cosmetic one.

- **A.** Accept the limit and document it: titles with |, ], [ or newlines aren't safely linkable; the picker should refuse or escape them — and include such a title in the test corpus so we know the failure shape before real data hits it
- **B.** Add escaping for reserved characters in the stored form (more robust, changes the on-disk grammar, needs round-trip tests)
- **C.** Constrain page titles at creation (disallow |, ], [) — pushes the limit to the title rule, which is a separate locked rule to amend

**▶ Recommendation:** Option 1 for this rebuild: accept + document + cover in the Phase-2 test corpus. The corpus the plan already calls for MUST include a title containing | and one containing ] so we at least KNOW the failure shape before real data exists. Don't invent escaping mid-rebuild; do prove the boundary.
  ◦ *Plain English:* 'Reserved character' = a character the format uses for its own structure (here | and ]), so it can't appear freely inside a title. 'Round-trip' = save then reload and confirm you got back exactly what you put in. 'Escaping' = a backslash trick that lets a reserved character appear safely inside text.

#### D4 · On-Disk — The 'collapsed heading' memory in each page is saved using the heading's exact text as a key (e.g. folded_headings: ['## Notes'], with '## Notes [2]' for a repeat). This format is already live in real files. Do we freeze it exactly, or switch to a more robust key (stable per-heading ids) while we're rebuilding?
*Why it matters:* If the rebuild changes how that key is computed even subtly — different whitespace trimming, different duplicate numbering — every page a user has already collapsed will silently forget its fold state and sections will spring open, which is the kind of quiet bug that erodes trust.

- **A.** Freeze the current format exactly (heading line trimmed of newlines; first occurrence bare, Nth duplicate gets ' [N]'); pin it with the Phase-2 tests — zero migration, zero behavior change
- **B.** Switch to stable per-heading ids during the rebuild — more robust against reordering duplicate headings, but changes the on-disk key shape and needs a migration
- **C.** Freeze the format now but add the duplicate-reorder and Windows-line-ending (CRLF) edge cases to the test corpus so we don't regress them

**▶ Recommendation:** Option 1 reinforced by Option 3's edge-case tests. The docs themselves flag stable-id keys as a deliberate 'v2 escalation if the ordinal scheme causes real friction' — there's no signal it's causing friction, so changing it mid-rebuild adds a migration burden for no current payoff. Critically, the reader is deliberately Windows-line-ending-tolerant today; that nuance must survive the rebuild verbatim.
  ◦ *Plain English:* 'Frontmatter' = the hidden settings block at the very top of a Markdown file. 'Key' = the exact text string used to remember which heading was collapsed. 'CRLF' = the Windows line-ending style; files from Windows or some sync tools use it.

### Hard-to-Reverse — expensive to change later

#### D10 · Module — When MarkdownPM becomes Pommora-owned, should it keep its current relaxed code-safety settings (older Swift mode), or be raised to match the strict safety rules the rest of Pommora uses?
*Why it matters:* The relaxed settings are the only thing currently letting ~11,000 lines of battle-tested editor code compile without a threading-safety re-audit; raising them would force exactly the re-audit of the verbatim-transplanted body that the 'transplant verbatim' lock exists to avoid.

- **A.** Keep MarkdownPM on its current relaxed settings (the package boundary stays the isolation seam, just renamed)
- **B.** Raise MarkdownPM to match the app exactly (uniform rules, but forces a threading re-audit of the verbatim body — a large hidden cost)
- **C.** Raise only the NEW brain files (parser/styler) to strict mode while the transplanted body files stay relaxed per-file

**▶ Recommendation:** Keep it relaxed (Option 1). The whole point of keeping it a package is to preserve this exact isolation; the Package.swift file itself spells out this concurrency-boundary reason. Raising it fights the 'transplant verbatim' lock head-on. Revisit only if a future feature genuinely needs it.
  ◦ *Plain English:* 'Strict concurrency' = a compiler mode that catches multi-threading bugs before the app runs, at the cost of more code ceremony. 'Swift 5.9 vs 6' = which version's rulebook the code is checked against. The package boundary is what currently shields the editor from the stricter rules.

#### D12 · Process — Two big in-flight efforts touch the same code: this MarkdownPM rebuild and a large parallel branch (a Folders + Relations refactor that is far behind main and deletes hundreds of tests). Which one should merge first, before the rebuild's new test net is built?
*Why it matters:* Building a brand-new test net while the other branch is mass-deleting tests in the same folder is a direct collision, and whichever branch merges second faces a large, risky reconciliation — so the order must be decided up front, not discovered at merge time.

- **A.** Merge the parallel Folders/Relations branch first, then start MarkdownPM on a clean main
- **B.** Ship MarkdownPM (at least Phase 1) first onto main, then reconcile the parallel branch against it
- **C.** Run them in isolated worktrees and explicitly plan the reconciliation as its own task before either merges

**▶ Recommendation:** Decide this explicitly before the rebuild's Phase-2 test net begins. My lean is to land the small, decoupled #9 fix (see D13) onto main first since it's tiny, then sequence the larger merges deliberately — but this is genuinely your call because the parallel branch's scope (305 files, deleting many tests) makes second-place reconciliation expensive either way.
  ◦ *Plain English:* 'Branch' = a separate line of in-progress work. 'Reconciliation / merge' = combining two diverged lines of work, which gets harder the more each has changed. 'Worktree' = a way to keep two branches checked out side-by-side without them interfering.

#### D26 · Parser — The big styler merge (Phase 5: collapse the two stacked stylers into one) — do we do it as one large change, as two safe stages (merge the easy constructs first, the cursor-aware ones last), or keep two passes that simply share one parse?
*Why it matters:* The full merge is the highest-risk step in the whole effort, and it must NOT break a locked rule that only ONE piece of code is allowed to set the appearance of cursor-aware dividers (a rule that already took two failed attempts to get right).

- **A.** Full merge in one change — maximum simplification, maximum risk
- **B.** Two passes sharing one parse: keep the inline/block split but feed both from the single cached parse — kills the duplicate-parse problem, lower risk, less cleanup payoff
- **C.** Full merge but STAGED — merge the safe constructs first (own commit), then fold in the cursor-aware ones last under their existing locked rule (own commit)

**▶ Recommendation:** Option 3 (staged). The single-styler destination is correct, but doing it as one commit is the riskiest step in the plan (4-6 sessions). Stage it so the merged styler keeps emitting NOTHING for the cursor-aware dividers (the locked 'sole-writer' rule); merge the safe constructs first, leave the caret-aware ones for last.
  ◦ *Plain English:* 'Block construct' = something spanning whole lines (a blockquote, a table). 'Inline construct' = something inside a line (bold, a link). 'Sole-writer' = a locked rule that only ONE piece of code is allowed to set a given construct's appearance, to avoid flicker.

#### D5 · Behavior — Nine little auto-typing transforms quietly rewrite what you type — and two of them change the actual saved characters: typing -- becomes a long em-dash (—), and a spaced - becomes an en-dash (–). The plan says 'transplant these verbatim' but never asks whether each is wanted. Do we ratify all nine as-is, or review the byte-changing ones first?
*Why it matters:* The em-dash and en-dash transforms are the only places where what you typed (--) is NOT what's saved on disk (—), and a test net is about to freeze all nine forever — so they should be a conscious 'yes,' not an accident of copying the file.

- **A.** Ratify all nine verbatim and lock them with tests (fastest; preserves current feel exactly)
- **B.** Ratify with a short review pass: specifically confirm the em-dash/en-dash on-disk substitution is wanted (Markdown purists sometimes keep literal --), then keep the rest
- **C.** Make the dash/arrow substitutions a user toggle (off by default for portability purists) — larger scope, a new setting

**▶ Recommendation:** Option 2 — a quick explicit confirmation pass before they're frozen. My read is you'll keep all nine, but the dash transforms deserve a deliberate yes because they're the only ones that change bytes-on-disk to non-ASCII characters. Note Pommora forces macOS's own auto-dash OFF to own this behavior, so there's no system fallback if we ever removed ours.
  ◦ *Plain English:* 'Input transform' = the editor silently changing what you typed (like autocorrect). 'On-disk effect' = it changes the actual saved file, not just the display. 'Em-dash / en-dash' = the long typographic dashes; 'canonicalize' = rewrite shorthand into the standard portable form.

#### D6 · Behavior — Today the editor always saves Markdown with Mac/Linux line-endings (LF) and rewrites any Windows-style (CRLF) file it opens. The plan never mentions this. Do we keep always-normalize-to-LF, or preserve whatever line-endings a file arrived with?
*Why it matters:* For a Windows-origin or synced file, opening and saving it in Pommora rewrites every line-ending, which shows up in version-control or collaboration as 'every line changed' — noisy and alarming even though nothing meaningful changed.

- **A.** Keep normalize-to-LF on save (simplest; consistent on-disk format; one-time diff churn for CRLF files) — and document it explicitly as intended so it's not mistaken for a bug
- **B.** Detect and preserve the original line-ending style per file on round-trip (more faithful for mixed-tool users; more code and a new thing to test)

**▶ Recommendation:** Option 1 + document it. Pommora is Mac-first / personal-first for v1; LF-everywhere is the sane canonical form. Preserving per-file CRLF is real complexity for a v1 audience that almost certainly isn't hitting it. The key action is simply to NOT let the rebuild accidentally introduce CRLF preservation OR break the existing CRLF-tolerant READ path the fold-key logic relies on.
  ◦ *Plain English:* 'Line-ending' = the invisible character at the end of each line; Mac/Linux use LF, Windows uses CRLF. 'Normalize' = force everything to one style. 'Diff churn' = a version-control view showing every line as changed even though only the invisible endings differ.

#### D7 · Parser — The plan promises the rebuilt parser will produce 'byte-identical' output, AND that it will delete the hand-written bold/italic parser and read emphasis from Apple's parser instead. These two promises contradict each other — Apple's parser disagrees with the old hand-written rules on tricky text. Which guarantee do we actually make?
*Why it matters:* If we demand byte-identical we have to keep the old hand-written code we were trying to delete (no real simplification); if we accept Apple's answer, styling shifts on some unusual text but the editor gets simpler and more standards-correct — so the team needs one clear instruction or a subagent will silently pick one.

- **A.** Demand byte-identical everywhere — keep the hand-rolled emphasis parser; Apple only fills gaps (defeats much of the simplification)
- **B.** Accept Apple's parser as the new source of truth for standard constructs; keep hand-written code only for the two Obsidian-only things ([[wikilinks]] and embeds); accept that styling shifts on rare edge inputs
- **C.** Accept Apple's answer but build the Phase-2 tests to FREEZE current behavior on a fixed set of documents, then consciously approve each intentional change those tests surface

**▶ Recommendation:** Option 3, and reframe the plan's promise. Don't promise 'byte-identical' — promise 'tested-identical on a fixed corpus, with each intentional divergence listed and approved by you.' The ~173-line hand-written emphasis parser is the single biggest deletable piece of accidental complexity in the whole effort — but only worth deleting if you accept Apple's emphasis behavior as the new truth.
  ◦ *Plain English:* 'Byte-identical' = produces the exact same result down to the character. 'AST' = the structured tree Apple's parser builds from the text. 'Emphasis / flanking / rule-of-3' = obscure standard rules for deciding what * and ** mean next to letters and punctuation. 'Corpus' = a fixed set of test documents.

#### D8 · Behavior — The per-kind rendering profiles let Items (short, capped, inline-only descriptions) render differently from Pages (full documents). The Item editor surface does not exist yet — the editor is only used in Pages today. Should we fully BUILD the Item profile now, or build only the hook (a switch) and keep it Pages-only until the Item Window is redesigned?
*Why it matters:* Building a fully-shipped Item profile now means designing a renderer for a screen that doesn't exist yet, against rules that aren't specced yet — so you'd likely rebuild it once the real Item Window lands, which directly fights Pommora's 'don't add complexity that wasn't asked for' rule.

- **A.** Build the .item hook (the seam/parameter) but leave it Pages-only and inert — .item is defined but never the active path until the Item Window redesign
- **B.** Fully build AND wire .item into a new Item description editor as part of this rebuild (expands scope significantly, designs a UI that isn't specced)
- **C.** Drop the profile concept from this rebuild entirely; add the parameter later when the Item Window is built

**▶ Recommendation:** Option 1. The seam is cheap and proves the architecture supports divergence; actually shipping the Item render is a separate feature gated on the Item Window redesign — which the Items spec itself explicitly defers ('Item-specific Markdown restrictions are deferred to the Item Window redesign'). Build the hook, keep it Pages-only.
  ◦ *Plain English:* 'Profile' = a settings-bundle telling the renderer 'this is a full Page' vs 'this is a short inline-only Item description.' 'Hook / seam' = the wiring is in place but switched off — like running a light switch's wires to a fixture you haven't installed yet. 'Consumer' = the part of the app that actually uses the feature.

#### D9 · Behavior — For the per-kind difference, should the styling values be ONE shared set (Items just turn off the block features they don't use) or TWO completely separate value sets (an Item theme and a Page theme)?
*Why it matters:* Items and Pages share the same inline look (bold, italic, links, inline code) and only differ in that Items suppress big block constructs, so two separate value sets would duplicate every shared color and risk the two drifting apart — exactly what Pommora's DRY rule forbids.

- **A.** One shared value set; the Item profile just DISABLES block constructs and optionally overrides a few inline values
- **B.** Two separate complete value sets (Item theme + Page theme) — more flexible, but duplicates shared values and invites drift
- **C.** One set now; revisit only if Items ever genuinely need different inline colors or sizes

**▶ Recommendation:** Option 1 — one shared value set, with the Item profile expressed as 'which constructs are allowed' plus a small override list, not a second full palette. Duplicating every shared color into a second set would violate DRY and create a maintenance trap; keep one source of truth and let the profile gate features.
  ◦ *Plain English:* 'Inline vs block constructs' = inline = bold/italic/links/inline-code within a line; block = headings, code blocks, blockquotes, dividers that take whole paragraphs. 'Override' = a single value that differs from the shared default, listed in one spot rather than copying the whole set.

### Reversible — my recommended defaults (veto any you dislike)

#### D11 · Parser — There's an untested guessing rule that decides whether $5 is money (leave alone) or $x+y$ is a math formula. It uses arbitrary thresholds (e.g. 'more than 120 words = not math'). It's flagged as the single riskiest untested thing in the parser. Do we copy it verbatim, copy-then-simplify after tests, or rethink it now?
*Why it matters:* If the rebuild changes this guess even slightly, a user's $5.99 could suddenly try to render as a broken equation or a real formula could stop rendering — and it has zero test coverage today, so nothing would catch the regression.

- **A.** Copy the rule verbatim into the rebuild and lock it with tests, no changes allowed
- **B.** Copy it but write tests first, then simplify the magic numbers only if tests still pass
- **C.** Rethink it now — replace the word-count thresholds with a cleaner rule, since there's no shipped math renderer to regress against yet

**▶ Recommendation:** Option 2. Reproduce it verbatim first and pin it with tests (it's load-bearing for which $...$ spans get marker-styling), but flag that the thresholds are pure guesswork with no current test coverage and no shipped math renderer behind them. Once frozen by tests, simplification is low-risk. Do NOT rethink it blind before the test net exists.
  ◦ *Plain English:* 'Heuristic' = a rough guessing rule, not an exact one. 'Currency-vs-math' = telling $5 (money) apart from $x^2$ (a formula). 'No-op stub' = the math-rendering code exists but currently does nothing, so the only visible effect today is whether the $ markers get styled.

#### D13 · Scope — Should the #9 caret-stutter fix (the one user-visible win in the whole rebuild) ship as its own release that users get immediately, or just sit as the first commit on the long rebuild branch?
*Why it matters:* The caret stutter is a daily per-keystroke annoyance and the fix is small (1-2 sessions), so making users wait the full 13-20 sessions of the rebuild for it would be the wrong tradeoff.

- **A.** Ship #9 as a standalone release (merge to main / tag) before any rebuild work — users get the fix now; the rebuild branches off the fixed main
- **B.** #9 is just the first commit on the rebuild branch — no separate release; users wait for the whole rebuild
- **C.** Ship #9 standalone AND hold the rebuild branch until #9 lands, to keep the merge story simple

**▶ Recommendation:** Option 1 or 3 — ship #9 standalone. The glitch is a per-keystroke annoyance and the fix is small; a clean main also makes the rebuild branch's merge story simpler. The plan's phrase 'ships alone' is ambiguous between 'a real release users receive' and 'just an internal checkpoint' — pick the former.
  ◦ *Plain English:* '#9' = a specific tracked editor bug: the text cursor stutters because every keystroke re-reads the whole document up to three times. 'Ships alone' is the ambiguous phrase — clarify it means a real release, not just an internal checkpoint.

#### D14 · Process — How much test coverage counts as 'enough' to safely start the rebuild — the plan's named 5-suite list as-is, or that PLUS a dedicated adversarial test pass on the two riskiest untested functions before any rewrite begins?
*Why it matters:* The plan states plainly that 'harness quality IS the safety' — if the test set misses an edge case, the rebuild will silently change how something renders or saves and no test catches it, and for the on-disk-affecting cases that means real user files could change unnoticed.

- **A.** Ship the 5 named suites over the listed corpus as-is and proceed (gaps stay invisible until production)
- **B.** 5 suites PLUS a corpus-review checkpoint before rewrite work begins, specifically targeting the on-disk-mutating cases (wikilink reserved chars, CRLF round-trip, em/en-dash byte output, duplicate fold-key headings, foreign-frontmatter preservation) and the two riskiest heuristics (currency-vs-math, emphasis)
- **C.** Require a measured code-coverage percentage on the parser files before the rewrite can start

**▶ Recommendation:** Option 2. The plan's corpus is strong on styling/parsing but light on the specifically on-disk-mutating cases — it lists CRLF and duplicate headings but not em/en-dash byte output, foreign-frontmatter preservation, or reserved-character titles. A deliberate corpus review against the on-disk decisions (D1-D6), plus pulling a few real pages from the nexus into the tests, is cheap insurance before a 13-20 session rebuild. A blanket coverage % is bureaucratic and can pass while still missing the actual edge cases.
  ◦ *Plain English:* 'Characterization test' = a test that records exactly what the code does today (even quirks) so a refactor can prove it still behaves the same — a photograph of current behavior. 'Adversarial corpus' = test inputs chosen to attack the hard edge cases, not just the typical ones. 'Silent regression' = it breaks but nothing alarms; you find out from a user.

#### D15 · Styling — The 'one styling file' goal already substantially exists as TWO files — one holding every color, one holding every size/spacing knob (18 grouped sub-sections). Do you want these merged into a single Pommora styling file, or kept as the proven color/metrics split, just renamed and tidied?
*Why it matters:* This decides what 'the single styling file' actually is, and a non-technical owner benefits from one navigable place far more than from a colors-vs-metrics split that only makes sense to a programmer.

- **A.** Merge into one file with clearly-labeled jump-to sections (Colors / Headings / Code / Lists / Blockquote / etc.) — truest to 'one file'
- **B.** Keep the existing two-file split (colors separate from sizes), just rename + re-home them as Pommora-owned and tidy the order
- **C.** Three files: Colors, Metrics, and Per-Kind-Profile overrides

**▶ Recommendation:** Option 1 — merge into one file with labeled sections. Your stated goal is a single navigable place; the 18 sub-groups can stay as headed sections inside the one file, preserving navigability without two files. This is a consolidation, not a from-scratch build.
  ◦ *Plain English:* 'struct' = a named bundle of related values in code (a labeled box of settings). 'MARK section' = a code comment Xcode turns into a jump-to heading, so you can navigate a long file by section. 'System color' = a color Apple defines that auto-adapts to light/dark mode.

#### D16 · Styling — The editor today uses Apple's system colors everywhere (which auto-adapt to dark mode), NOT fixed Pommora-brand colors — and a brand theme overlay (brand purple, custom callouts) is explicitly DEFERRED to the v0.4.0 Settings work. Should MarkdownPM keep the current system-color defaults, or set brand colors now?
*Why it matters:* Setting brand colors now pulls deferred work forward, risks locking a palette before the Settings UI exists to let users change it, and means you'd take on providing both a light and dark version of every color (system colors do that for free).

- **A.** Keep system-color defaults exactly as-is, but ROUTE every color through a named slot so swapping in brand colors later is a one-line edit (brand work stays deferred to v0.4.0)
- **B.** Set the three named brand slots now (code color, blockquote bar, callout border) and leave everything else system-driven
- **C.** Replace broadly with a fixed Pommora palette now (most work; locks the look before Settings exists)

**▶ Recommendation:** Option 1 — keep system colors, preserve the deferral, but route everything through named slots. The rebuild's goal is consolidation and DRY, not a visual redesign; bundling a brand palette in front-runs the v0.4.0 Settings work that's meant to own accent and customization. The slots make the future brand swap a one-line change.
  ◦ *Plain English:* 'System color vs fixed color' = a system color (like labelColor) changes itself for light/dark mode; a fixed color (a specific purple) does not and needs two versions. 'Route through named slots' = the code asks for theme.codeColor rather than writing the red directly, so changing it later touches one line.

#### D17 · Styling — Some brand-meaningful visual values (the blockquote card and accent bar, the divider line, the bumped-up bullet size, the checkbox tint) physically live inside the renderer — the part the plan says to transplant 'verbatim.' Which of these values get lifted into the single styling file, knowing that means the verbatim renderer must READ them from the styling file?
*Why it matters:* Centralizing these values requires reaching into code the plan says to copy untouched, so there's a real tension: you can make the values settable, but over-extracting could destabilize the verbatim transplant the rebuild depends on staying stable.

- **A.** Lift the brand-meaningful COLORS (code color, blockquote card fill + bar) into named slots; leave pixel geometry (bar width, corner radius, indents, margins) as layout constants in the draw code
- **B.** Lift ALL values (colors AND geometry) into the styling file; the draw code reads everything from it
- **C.** Leave all renderer-resident values in the verbatim renderer for now; the styling file only covers styler-side values (a meaningfully smaller file)

**▶ Recommendation:** Option 1 — lift the colors (the brand-meaningful, likely-to-change values) into named slots, leave the pixel geometry with the verbatim draw logic it's tightly coupled to. This honors 'the values file = the stuff you'd actually retheme' without fracturing the transplanted renderer. The key thing you must rule on: whether reading-a-value-from-config counts as 'modifying' a verbatim file (assumption A6 below).
  ◦ *Plain English:* 'Renderer / draw code' = the low-level machinery that paints text on screen, kept verbatim because it works around macOS bugs. 'Geometry vs color' = geometry is shape/size (width, radius); color is the paint. 'Card fill / accent bar' = the rounded grey box behind a quote and the vertical line on its left edge.

#### D18 · Styling — Heading sizes are a list of multipliers where H4 renders at exactly body-text size and H5/H6 render SMALLER than body text (the classic browser default). Are these the heading sizes you want, given a level-5 heading looking smaller than a paragraph can read as a bug?
*Why it matters:* It's a real, already-shipped styling value the rebuild will carry forward, and sub-body H5/H6 can surprise people — harmless if Pommora pages rarely go past H3, but it reads as intentional or as a bug depending on how deep headings nest.

- **A.** Keep the current browser-default ratios (H4 = body size, H5/H6 smaller than body)
- **B.** Adjust so H4-H6 stay at or above body size (headings never shrink below paragraph text)

**▶ Recommendation:** Option 1 for now (keep the shipped ratios), but I'm flagging H5/H6 shrinking below body size as a likely surprise — if deep heading nesting is expected, Option 2 reads more intentionally. Either way these belong in the unified styling file's Headings section. Just confirm sub-body H5/H6 is intended before the test net freezes it.
  ◦ *Plain English:* 'Multiplier' = a factor applied to the base font size; 2.0x means twice as big, 0.67x means two-thirds the size. 'Body size' = the size of normal paragraph text.

#### D19 · Module — Should the app's main entry point to the editor keep its current donor-heritage name (NativeTextViewWrapper) or be renamed to a Pommora-branded name?
*Why it matters:* This is the single named building-block the rest of the app uses to show the editor; the current name carries the original donor library's heritage, and a Pommora-owned module arguably should present a Pommora-named front door.

- **A.** Keep NativeTextViewWrapper — zero churn, but keeps donor-heritage naming on the public front door
- **B.** Rename to PommoraMarkdownEditor (or MarkdownEditorView) — Pommora-branded, matches the internal styler naming, a one-time mechanical update to a single call site
- **C.** Keep the low-level type but add a thin Pommora-named wrapper on top

**▶ Recommendation:** Option 2 — rename it. The app references it at one call site, the change is mechanical, and a Pommora-owned module should present a Pommora-named front door rather than carry the donor library's type name. Avoid option 3 — it adds a layer for no functional gain.
  ◦ *Plain English:* 'Public entry point / front door' = the one named building-block the rest of the app uses to show the editor. 'NSViewRepresentable' = the Apple glue that lets an old-style Mac text view live inside the newer SwiftUI screen layer.

#### D20 · Module — The editor's front door currently accepts 14 settings/hooks but the app uses only 7; the other 7 are dormant (link-click handlers, paste-image hooks, inline-replacement plumbing). Do we keep all 14, trim to the 7 the app uses, or keep only the seams the imminent wikilink work will need?
*Why it matters:* Several dormant inputs are exactly the connection points the wikilink feature and future autocomplete will ride on, so shedding them now means re-adding them in the very next phase — but keeping truly speculative ones makes the interface look richer than it is. Note the plan mis-describes this as a '7-param init'; the real init has 14 params.

- **A.** Keep all 14 — the dormant ones are documented seams for wikilinks/autocomplete/image-embed that are coming
- **B.** Trim to only what the app uses today (~7) — leanest, but re-grow it when wikilinks land
- **C.** Keep the wikilink/inline-selection/replacement/paste seams the in-flight wikilink work will demand; shed only the genuinely speculative formatting hooks the app never wires

**▶ Recommendation:** Option 3 — keep the inputs the wikilink work will need, shed only the speculative ones. This honors 'simplicity-first' without amputating seams the roadmap needs next phase. Important correction for the plan: it says '7-param init' but the real init has 14 params; the builder must not literally build a 7-param front door and silently drop the wikilink seams.
  ◦ *Plain English:* 'Input / param' = a setting or hook you hand the editor when you create it. 'Dormant seam' = a connection point built but not yet plugged in. 'Notification bus' = a message channel the editor could use to tell the surrounding UI something changed, currently unused.

#### D21 · Module — Confirm the new module name MarkdownPM, and confirm that Pommora-branded type names like PommoraMarkdownStyler are allowed despite the 'Pommora prohibited in Swift namespace' rule.
*Why it matters:* The module name becomes the 'import' every file writes (changing it later is another rename pass), and 'PM' commonly reads as 'Package Manager' in Swift tooling — so the name is a one-time identity choice worth a deliberate yes; separately, the brand-name rule needs a read so the plan's already-chosen type names aren't accidentally rule-violating.

- **A.** MarkdownPM module, public types prefixed PommoraMarkdownStyler etc. (plan's assumption)
- **B.** A clearer Pommora-branded module name (e.g. PommoraMarkdown) if 'PM' reads too much like Package Manager
- **C.** MarkdownPM module but a non-brand type prefix to stay clear of the namespace rule's spirit

**▶ Recommendation:** Confirm MarkdownPM (it's clean and Pommora-owned), and bless the PommoraMarkdownStyler type-naming. The rule bans 'Pommora' only as a namespace-qualifier trick (like Pommora.Task), NOT as an ordinary type name like PommoraMarkdownStyler — those are different and the latter is the sanctioned pattern (same as AgendaTask). Worth a deliberate yes since the rule is sensitive.
  ◦ *Plain English:* 'Module' = the named code library the app imports (today MarkdownEngine). 'Type prefix' = the leading word on a class/struct name. The hard rule bans Pommora only as a namespace-qualifier workaround, not as a normal type name — these are genuinely different.

#### D22 · Module — The plan currently places the NEW Pommora styler/services files OUTSIDE the package, in the app itself. Since the locked decision is that MarkdownPM is THE owned editor module, should the new styler code live INSIDE the package instead?
*Why it matters:* If new styler code lands in the app while the body stays in the package, the 'one owned module' story fractures — the editor's brain is half-in, half-out, the package can't be tested in isolation for the styler, and a future editor swap would touch two locations.

- **A.** Put all new styler/services code INSIDE MarkdownPM (the owned module) — keeps one coherent editor module
- **B.** Keep new Pommora-side files in the app target as the current plan/changelog notes suggest — splits the brain across two trees

**▶ Recommendation:** Option 1 — new styler code goes inside MarkdownPM. The plan's own re-home goal and the 'one owned module' lock both point here; the changelog note placing new files in the app target contradicts that and should be corrected before the styler rebuild (Phase 5).
  ◦ *Plain English:* 'Package vs app target' = whether code lives in the self-contained editor library or in the main app. 'Tested in isolation' = able to run the editor's own tests without launching the whole app.

#### D23 · Process — Should this rebuild hold the parser's dependency on Apple's swift-markdown pinned to exactly version 0.8.0 throughout, then do a separate controlled version-bump afterward — or update it as part of the re-home?
*Why it matters:* The whole rebuild rests on this one library's exact behavior, so bumping it mid-rebuild would make it impossible to tell whether a styling change came from your code or the library — but staying pinned forever means never getting upstream fixes (possibly including a known text-position bug).

- **A.** Hold 0.8.0 fixed for the entire rebuild (tests stay calibrated to this version), then do a deliberate, isolated bump afterward with tests re-run
- **B.** Update to the latest version as part of the re-home, then re-baseline the tests (gets fixes but absorbs behavior changes mid-rebuild)

**▶ Recommendation:** Option 1 — hold 0.8.0 fixed through the rebuild, bump deliberately afterward. Never change the parser version in the same change as the rebuild. There's a known latent bug at this boundary (Apple counts character positions one way, Pommora's code assumes another, which misaligns on emoji/accented text); a later bump might fix or worsen it, which is another reason to isolate the bump.
  ◦ *Plain English:* 'swift-markdown' = Apple's official library that reads Markdown into a structured tree. 'Pinned to exactly 0.8.0' = locked to one specific version. 'UTF-8 vs UTF-16 offset' = two ways of counting character positions that disagree on emoji and accented letters.

#### D24 · Parser — How aggressive should the 'strict DRY' cleanup be — only the duplicated parser/styler logic the plan names, or also any adjacent duplication the rebuild bumps into along the way?
*Why it matters:* An over-aggressive 'while we're in here' cleanup that touches the verbatim body files re-incurs the exact debugging the verbatim-transplant rule exists to avoid, while conservative cleanup leaves some duplication but is far safer.

- **A.** Conservative — clean up ONLY the named brain targets; treat every verbatim body file as off-limits even if it duplicates something
- **B.** Moderate — the named targets plus any duplication wholly inside the parser/styler, but never touching files in the preserve-verbatim list
- **C.** Aggressive — chase all duplication the rebuild surfaces, including light touches to body files

**▶ Recommendation:** Option 2 (Moderate). It honors strict-DRY where it's safe (the brain, which has the test net) and draws a hard line at the verbatim body. Aggressive DRY directly contradicts the plan's own scope-creep guard.
  ◦ *Plain English:* 'DRY' = Don't Repeat Yourself — collapsing copy-pasted logic into one shared function. 'The brain' = the parser + styler (being rebuilt). 'The body' = the TextKit/AppKit files with OS-bug workarounds (kept verbatim).

#### D25 · Parser — The 'is the cursor on this thing right now?' check (which reveals/hides raw syntax as you type) is answered in ~9 scattered spots that don't all agree. Do we reproduce the existing slightly-inconsistent behavior exactly, or unify it into one rule that may shift a couple of edge cases by a single character?
*Why it matters:* Unifying is the whole point of the rebuild, but it can make a marker reveal or hide one keystroke earlier or later in corner cases — and two of those spots are genuinely special on purpose, so a blind merge could break them.

- **A.** Reproduce byte-for-byte: port each spot's exact edge logic into one function with per-construct flags so nothing visibly changes
- **B.** Unify to one clean rule and accept that a few edge cases may reveal/hide one position differently
- **C.** Unify the common case but keep documented carve-outs for the two genuinely-special cases (math-selection-overlap and the task-checkbox end-of-syntax reveal)

**▶ Recommendation:** Option 3 — unify into one caret-context function but preserve the two real carve-outs as explicit branches. The scattered code is mostly copy-paste drift, but two cases ARE intentionally special and must survive: math activates on any selection that overlaps it, and the checkbox has its own end-of-syntax reveal. Lock those; unify the rest.
  ◦ *Plain English:* 'Caret' = the text cursor. 'Token' = one recognized Markdown thing (a link, a bold span). 'Marker' = the raw syntax characters (**, #, [[). 'Reveal/hide' = whether you see the raw syntax or the styled result.

### Awareness — no decision, but you must know

- **The wikilink rename-safety contract the plan treats as something it's preserving does not actually exist on disk yet — the app injects no resolver, so every wikilink today is saved as plain [[Title]], never [[Title|<id>]]. Verified: zero resolver conformances in the app, and no id-bearing wikilinks in any real page on disk.** — The plan reads like it's protecting an existing format, but Phase 3 is actually the first-ever activation of a brand-new permanent on-disk format — which is a paradigm-level decision that should go through your confirmation protocol, not slide in as a refactor step. The rename-safety promise users might assume exists, does not yet.
- **The 'package boundary' is not just tidiness — it's the active mechanism letting the verbatim body compile under looser safety rules than the app. Folding MarkdownPM into the app would silently force a threading-safety re-audit of the ~18 untested OS-bug workarounds. Package.swift itself spells out this reason.** — The 'package vs fold-into-app' open question looks like a cleanup choice, but folding in would quietly break the verbatim-transplant guarantee. The two locked decisions ('keep it a package' and 'transplant body verbatim') are really the same decision wearing two hats.
- **The plan's 'public contract' section says '7-param init' and 'the other 7 may be shed,' but the real front door has a 14-param init (the app uses 7). Verified directly in the code.** — If a builder takes the plan literally and builds a 7-param front door, they may silently drop the wikilink/inline-replacement/paste seams the very next roadmap feature needs. The contract section needs correcting before it's used as the build spec.
- **The plan promises 'byte-identical' parser output AND deletion of the hand-written emphasis parser in favor of Apple's parser — but those two goals contradict, because Apple's standard emphasis rules differ from the old hand-written ones on adjacent and intra-word cases.** — The plan makes a promise it can't keep. Reframe it as 'tested-identical on a fixed corpus, with each intentional difference listed and approved by you' — otherwise a builder will either keep the old code (no simplification) or silently change styling on edge cases (no safety).
- **The entire rebuild is roughly 13-20 sessions across 6 phases, and the ONLY user-felt improvement in that whole span is the Phase-1 caret fix. Phases 2-6 are internal architecture with zero new visible features.** — This is a large internal-quality investment, not a feature delivery. You should approve it knowing the payoff is maintainability, one owned module, fewer parses, and the Item-profile capability — NOT something users will see. This is also why shipping the small Phase-1 fix on its own matters so much.
- **There is NO running safety net over the ~11,000 lines of editor code until Phase 2 lands — the engine's existing tests live in a target the app's normal test command doesn't run. So today the editor is effectively untested in the app's checks.** — Until Phase 2 completes, anyone starting parser/styler work would be refactoring blind. The sequencing lock (test net BEFORE rebuild) is load-bearing, not ceremonial — and it's slightly in tension with Phase 1 shipping before Phase 2 (see assumptions).
- **A large parallel branch is in flight that is NOT just a small wikilink tweak — it's a 305-file Folders + Relations refactor, far behind main, that deletes hundreds of tests. The working tree is also actively changing between dispatches (a planning doc was deleted mid-task).** — Building a new test net while another branch is mass-deleting tests in the same folder is a direct collision, and whichever branch merges second faces a major reconciliation. The merge order needs deciding before the rebuild starts, and no builder should ever revert unattributed working-tree changes.
- **Two of the auto-typing transforms write non-ASCII characters to disk on a single keystroke: -- saves a literal em-dash (—) and a spaced - saves an en-dash (–). The en-dash transform already has a special carve-out to NOT fire inside wikilink filenames, showing the team already knows it can corrupt intended literal text.** — Pommora's whole paradigm is 'files are canonical and externally legible,' and these are the rare places where what you typed is NOT what's saved. It's a defensible typography choice, but worth knowing it exists before a test net freezes it forever.
- **Frontmatter preservation (keeping plugin/Obsidian fields Pommora doesn't understand) happens entirely in the app's save layer, NOT in the editor engine being rebuilt — the editor only ever touches body text. Verified.** — This is reassuring: the MarkdownPM rebuild cannot accidentally destroy users' foreign frontmatter, because that data never passes through the engine. One less thing to worry about — but it also means the engine's tests won't cover frontmatter round-trips; that protection lives in a different suite this plan doesn't touch.
- **The empty []-checkbox behavior was finalized just one day before this plan: a bare -[] is treated as a list line but NOT drawn as a checkbox until you type the content-space, which rewrites it to - [ ]. The list-detection and checkbox patterns are deliberately DIFFERENT here.** — This is the freshest, most fragile behavior in the editor and the one most likely to get 'cleaned up' wrong during a DRY consolidation. A well-meaning 'one source of truth' merge of these patterns would silently break the shorthand you just designed.
- **The genuinely public, app-facing API is tiny: one entry-point view, the configuration struct (of which the app sets ONE field), two text-attribute keys, and two helper functions. Everything else the plan frames as 'contract' (the internal token type, the tokenizer, detection internals) is package-internal.** — This narrows what must be frozen vs what can be freely refactored. The expensive-to-preserve 'byte-identical token output' is an internal concern guarded by tests, not a public promise — so the Phase 4 parser rebuild has more freedom than 'must not break public contract' implies.
- **Locked paradigm #7 in the decision registry still reads 'vendored swift-markdown-engine.' The plan says to record the rename in History.md but doesn't mention updating that registry entry — and both the plan and CLAUDE.md miscite the Markdown spec doc's location (it lives under Guidelines, not Features).** — If only History.md is updated, the canonical paradigm registry will still say 'vendored,' creating exactly the cross-doc contradiction Pommora's doc rules forbid. Both the registry entry and the doc-path citations should be fixed as part of the re-home.
- **There's a known latent bug carried forward: Apple's parser reports text positions in UTF-8 bytes while Pommora's code treats some as UTF-16 units, misaligning styling on emoji/accented/non-Latin content (most likely in tables). The rebuild leans MORE on Apple's parser, so this bug's exposure surface grows.** — It's invisible for plain English but real for multi-byte content, and routing more constructs through the same position-converter makes it more reachable. Worth a deliberate decision: fix it during the rebuild while you're in there, or explicitly keep deferring it.
- **The collapsed-heading fold state is on-disk data (folded_headings: in page frontmatter), and the heading-key format with its [N] duplicate suffix and Windows-line-ending handling is therefore already on-disk-locked — the rebuild must not change it even incidentally.** — If the parser rewrite changes how a heading's fold-key is computed, every page where a user collapsed a heading loses its saved state — the keys won't match. This is real data in real files, so the test net must lock the exact key output, not just the function name.

### Assumptions to confirm

- The app's coupling to the editor really is just 3 import sites and a small set of symbols (verified: exactly 3 files import the engine), so the rename + contract-preservation is low-churn — BUT the configuration.services seam the app also touches must be confirmed intact, since it's part of the contract too.
- The shipped look (softened-red code text, grey blockquote card, bumped 1.5x bullet, system colors throughout) is what you've SEEN and are content to keep AS-IS through the rebuild — i.e. this is a consolidation, not a visual redesign — because the Phase-2 test net will LOCK the current look as 'correct,' making a later visual change fight the tests.
- The Item profile renders strictly inline-only (no headings, code blocks, blockquotes, dividers, tables, images), so its styling needs only the inline value subset — if Items are actually meant to render SOME block constructs, the profile design and the one-shared-value-set decision both change.
- Phase 1's #9 fix (collapsing the triple-parse onto one cached parse) is purely a performance change with NO visible styling change — but it's sequenced BEFORE the test net exists, and the slow functions it deletes are the SAME ones the dash/checkbox transforms call to decide 'am I inside code?', so it touches behavior, not just speed, and needs the same test coverage that doesn't arrive until Phase 2.
- Reading a value FROM the styling file inside a verbatim renderer file does NOT count as 'modifying' that verbatim file — because if 'verbatim' is read strictly (touch nothing), then no renderer-resident brand value (blockquote bar, divider line, bullet size) can be centralized, and the 'single styling file' goal shrinks to styler-side values only.
- Naming new types with a 'Pommora' brand prefix (PommoraMarkdownStyler, PommoraWikiLinkResolver) is permitted and not blocked by the 'Pommora prohibited in Swift namespace' rule — if you read that rule as banning ALL Pommora-prefixed type names, the plan's already-chosen names violate it and every new type needs renaming.
- The Phase-2 test corpus's enumerated construct list is COMPLETE — every Markdown/Obsidian construct the editor handles today is represented — because 'harness quality IS the safety' means an incomplete corpus is an incomplete safety net, and there are 20+ Pommora-specific behaviors each of which must be covered or risk silent regression.
- Activating the wikilink resolver in Phase 3 will NOT commit users to an on-disk wikilink format, because no real wikilink data exists yet and the format is still being finalized in a separate track — if the resolver goes live and writes ids before that track lands, every linked file is locked to a format that may then need a migration.
