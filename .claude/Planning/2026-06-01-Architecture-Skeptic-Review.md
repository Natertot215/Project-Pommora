## Architecture Skeptic Review — 2026-06-01

Durable record of a graph-assisted skeptical review of Pommora (built via a knowledge graph over docs+code + four parallel skeptic agents). This is **pre-implementation analysis** — findings + recommendations, not a ratified plan. Keep it as the seed for the v1 architecture decisions it raises.

### Meta-thesis

Pommora keeps building **two of things that are one thing**, and has frozen **product bets** as if they were **data contracts**. Its real, defensible identity — *a native, file-owned, agent-legible knowledge graph* — is strong; the work is collapsing the accidental forks so that identity isn't buried under symmetry. The paradigm-decision protocol is good for *data-shape* stability, but it leaked into freezing UX/product architecture (Items-vs-Pages, filename=title, popover Item Window, the Vault/Set vocabulary) that should have stayed fluid.

### Load-bearing constraints to second-guess

- **"Files are canonical" is two claims.** Files as the canonical *read/ownership* surface = genuinely load-bearing (the identity vs Notion: plain files, git-diffable, Obsidian-editable). Files as the canonical *write/query* path = an **expensive assumption**: ~4.7k LOC + ~27% of the test budget serve it; an 11-table SQLite mirror was built anyway (files can't be queried); "cloud-sync for free" is asserted but unbuilt (no `NSFileCoordinator`); it manufactured a recurring FK-resync defect class + the title-collision data-loss bug. North-star to weigh (not v1): **DB-canonical + files as a continuously-exported mirror**; the cost is external write-back (the deferred file-watcher).
- **"Agent legibility" is the named differentiator** — real, but satisfiable by a read-mirror; doesn't require files to be the write path.
- The two docs that define the "load-bearing set" disagree (Architecture.md = 2 principles; CLAUDE.md = 3) — the canon isn't internally consistent.

### Items vs Pages — the most expensive accidental fork

~7,700 LOC of near-copy-paste across 8 layers + 6 near-identical SQLite tables. `ItemValidator.validate` literally takes a `vault: PageType`; `PageFrontmatter`'s own comment says *"Mirrors Item shape minus description."* An Item **is** a Page with the body cap down — the difference is *one field* (250-char description vs body) and *one render target* (popover vs pane). Recommend collapsing to one `Record` (optional body) → reclaims 3–4k LOC, makes Item↔Page promotion free. Pragmatic middle path: keep two serializations, unify the type system (~80% of the win). The "Vault/Set" dual vocabulary is clever-tax — drop it.

### The bespoke editor — right bet, wrong burn rate

~29% of all code, #1 god node, 13% of commits — the gravitational center. The native bet is *strategically right* (the moat is macOS system integration + no-Electron, NOT folding/previews, which web editors do for free). The bleed is the **caret-pixel-perfection arms race** chasing named Apple bugs via private internals. KEEP the done core; DEFER tables/LaTeX/syntax-highlight/find; CUT the caret micro-fixes; GUARD with a CI smoke test.

### Constraint audit — wounds vs rented problems

- env-injection fragility = self-imposed wound → **FIXED** (`NexusEnvironment`).
- Sidebar crash-fragility = *rented* from Apple's private `List` diffing, mis-attributed in docs as own-code.
- "EventKit-shaped Agenda" = mislabeled (no `import EventKit`; just borrowed field names) — fix the phrasing; stop pre-locking sync fields.
- "No `Pommora.X`" naming rule = **keep** (cheap, clearer).
- "Relations always multi-value" = **keep** (clean uniformity); doc self-contradicts on chips-vs-text.

### Truly strong (don't touch)

ID-keyed rename-safe relations + tiers-as-relations through one table (graph-ready, underexploited); per-Type schema in filename-discriminated sidecars (the *good* half of files-canonical); the atomic-write discipline; the native-editor *thesis*; the paradigm-decision confirmation protocol.

### Feature opportunity — lean into the graph

The data model is *already a graph* (ID-keyed relations, one `relations` table). Ship the **graph view + MCP server** as the headline ("your nexus is natively an agent-queryable knowledge graph") — it beats Notion (no graph) and Obsidian (unstructured graph). Also reconsider the rigid fixed-depth-3 Context hierarchy (tiers are already relations under the hood).

### Recommended sequence

1. Fix the title-collision data-loss bug — **DONE** (extended to all entities + moves; see Status).
2. Hoist the env-injection container — **DONE** (`NexusEnvironment`).
3. **Unify Items+Pages** (highest ROI; the middle path first). — **SUPERSEDED 2026-06-02 by the Items-as-Markdown serialization unification** (`Planning/Superseded/2026-06-01-Items-as-Markdown-Plan.md`): the middle path is the chosen route — Items become plain `.md` on Pages' one `AtomicYAMLMarkdown` pipeline (capped body = description, Shape A), collapsing the two serializations while Items / Pages stay distinct *forms* of one entity. Item↔Page promotion is now a cheap retype + container move (see [[Prospects]]). The full single-`Record` collapse + the "Vault/Set" vocabulary drop are NOT taken; they remain open.
4. Stop editor polishing; redirect to thin areas (Agenda/Settings/QuickCapture) + the graph.
5. Decide cloud-sync as **DB-canonical** now (don't lock "files are the write path").

### Status (2026-06-01)

Items 1–2 implemented + verified (1073 tests, 0 failures; flake fixed). Item 1 grew during code-review into the full title-collision fix: **reject** on create/rename/move across Pages, Items, Agenda Tasks/Events + the 6 container types, with a self-recase allowance (inode-identity rename guard) — registry decision #13. Item 2 = the `NexusEnvironment` single-injection container. Both **uncommitted in `main`'s working tree** pending a commit decision. Items 3–5 are open architecture threads (this doc is their seed).
