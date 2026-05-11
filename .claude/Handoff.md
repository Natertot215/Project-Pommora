### Pommora — Session Handoff

#### Current State

Three-entity domain model locked: **Pages** (Markdown files), **Collections** (folder + `_collection.json` schema sidecar), **Spaces** (`.space.json` block trees). Per-entity feature specs live in `// Features//Pages.md`, `// Features//Collections.md`, `// Features//Spaces.md`.

Architecture framing is **conceptual portability of functionalities** — file formats, schemas, semantic operations, design tokens, and UX patterns survive a stack rebuild; the codebase doesn't. No enforced layer separation; the portability comes from documented decisions, not code structure.

Both stack paths (React+Electron and SwiftUI) are fully audited. Per-stack deep references in `ReactInfo.md` and `SwiftInfo.md` are parallel-structured for direct comparison; `Resources.md` catalogs external libraries per stack. The PRD's dual-stack table summarizes the side-by-side.

No code yet — `.claude//` contains project specs only.

---

#### Immediate Decisions

1. **Stack** — React+Electron or SwiftUI. **Gating decision for everything else.** All research is in: `ReactInfo.md`, `SwiftInfo.md`, the PRD dual-stack table, and `History.md`'s editor section. The mirror-image tradeoff: React makes the editor easy and Mac integration ~80%; SwiftUI makes Mac integration 100% and Phase B editor a real R&D project.

2. **Project license** — what Pommora ships under (MIT, Apache, GPL-3.0). Affects the React path specifically: BlockNote's `xl-multi-column` is GPL-3.0 viral OR $195/mo commercial. A permissive license means custom multi-column block in BlockNote core; GPL-3.0 means `xl-multi-column` is fine. Independent of but coupled to the stack call.

---

#### Immediate Explorations

- **Figma file setup** — design system foundations (colors, typography, spacing, three-pane shell components). Stack-agnostic at the token level; can run parallel to the stack decision. Use `figma-use` skill.

- **Audit findings to commit or defer** — `chokidar` → `@parcel/watcher`, `@dnd-kit/core` v6 pin, Zod validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety, `gray-matter` alternatives. Currently captured as findings, not committed. Decide which to lock in once the stack lands.

- **Spike before commit (optional)** — if the stack call wants empirical validation before locking: spike BlockNote markdown round-trip with a custom serializer for `:::columns`, OR spike SwiftUI `TextEditor` segment-based render to size the cross-segment cursor problem. Either spike is bounded; neither is required.

---

#### Open Questions

- **Stack:** React+Electron or SwiftUI?

- **License:** what does Pommora ship under?

- **Design (lower priority):** Figma file location and naming; default font choice (system stack vs opinionated); shell layout proportions (sidebar 240px, inspector 280px proposed in v0.0).

---

#### Recent Changes (this session)

- **Per-entity feature docs created.** Pages, Collections, and Spaces each got a dedicated detail doc in `// Features//` (`Pages.md`, `Collections.md`, `Spaces.md`). `Domain-Model.md` trimmed to a brief overview that links to the per-entity files plus retains cross-cutting topics (linking model, properties summary, sidebar, resolved decisions). PRD and CLAUDE.md Document Map updated to point to the new structure.

- **Phase B Swift editor reframed as committed post-v1 core feature.** Was previously framed ambiguously (in-scope for SwiftUI path); now explicitly: Phase A = v1 (native `TextEditor` + quick fork for H4-H6 + toggles); Phase B = committed post-v1 (full custom editor with hover-on-selection bubble toolbar). Phase B is a must-have eventually for the Swift path, not Prospects. Captured in `Pages.md`, `SwiftInfo.md`, and `History.md`.

- **Architecture simplified.** Dropped the three-layer enforcement model (Core / Adapter / UI separation rules; "Core has zero UI imports" rule) as over-engineered for indie development. New framing: **conceptual portability of functionalities** — file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design tokens, and UX patterns are designed to survive a stack rebuild. The codebase isn't pre-arranged for hot-swap; portability comes from documented decisions, not enforced code structure.

- **Files reorganized.** `Resources.md`, `ReactInfo.md`, `SwiftInfo.md` moved from `// Features//` to `.claude/` top level — they're cross-stack reference catalogs, not per-entity feature specs. All path references across the project updated.

- **Doc-convention restructure landed.** Introduced a `**For React**` / `**For Swift**` labeling convention within shared docs (PRD, Architecture, Domain-Model, Prospects, UIX-Guide) so stack-conditional content is visibly distinct. Created `// ReactInfo.md` as parallel to `SwiftInfo.md` (mirror structure section-for-section). Convention + exceptions (comparison tables, catalogs, stack-locked specs) documented in `CLAUDE.md`'s Document Map. Fixed long-standing `UIX-Guide.md` path discrepancy in CLAUDE.md / PRD / Architecture (file lives in `// Guidelines//`, not `// Features//`).

- **Research cycle 2 — tools and considerations dive.** Four parallel agents covered build/distribution, Mac OS integrations, editor internals, and state/data layer for both stacks. Findings landed in `Resources.md` and `SwiftInfo.md`. Key reads:
  - **Distribution is a wash.** Both stacks ship cleanly to MAS (security-scoped bookmarks pattern is identical) and have production-grade auto-update (electron-updater / Sparkle 2.x). React edges on dev loop (electron-vite HMR); SwiftUI edges on first-party tooling.
  - **Mac OS integrations lean materially toward SwiftUI.** QuickLook (.md preview via Finder spacebar), Share Extensions, CoreSpotlight, Finder file-promise drag-out, sidebar vibrancy, and accessibility all show meaningful gaps in pure Electron. Equal: app menu, deep links, basic notifications, dark-mode toggling.
  - **SwiftUI editor segment-render is the load-bearing risk.** No shipped Mac app uses the segment-based pattern Pommora's plan calls for; Bear / iA Writer / Craft all use single-text-view-with-decorations to avoid the cross-segment cursor problem. Mitigations: treat per-segment selection as a feature (Notion-like), or drop down to STTextView if cross-segment becomes a hard requirement.
  - **BlockNote markdown is lossy by design** (now confirmed in official docs). Custom serialization is achievable via per-block `toExternalHTML`/markdown handlers, but covering every block type *is* the canonical-format guarantee — not a small layer on top.
  - **State + data patterns confirmed for both stacks.** React: Zustand vanilla (Core) + hand-rolled table-keyed pub/sub (~80 LOC, ports to Swift) + better-sqlite3 + FTS5 (`unicode61`) + @parcel/watcher v2.5+. SwiftUI: `@Observable` + GRDB.swift v7.5+ + `ValueObservation` + FSEventStream wrapper. SwiftData remains unsafe for "files canonical" use cases.

- **Property catalog refined** — no free-form text property; title is the filename; "text-shaped" values use Select / Multi-select with creatable options (Notion behavior). `// Features//Properties.md` updated.

- **Callouts spec locked** — visual container with optional color, no icons or semantic types, single design pattern, composes with `@Columns` for side-by-side. PRD + Domain-Model + History updated.

- **Columns spec locked** — equidistant width division by child count in v1; no per-column width config (no inline attrs, no sidecar layout file). Adjustable widths deferred. PRD + Domain-Model + History updated.

- **Spaces framing clarified** — page-like canvas with drag-and-drop blocks, Notion-style structured layout (1D vertical flow with one nestable `columns` container), not free X/Y positioning.

- **Cloud-sync mapping fixed in PRD** — corrected from "each Collection → one cloud table" to "shared `pages` table with `collection_id + properties JSONB`" (matches local SQLite shape and Notion / Airtable / AFFiNE convention). It's a prospective feature, not currently in-scope.

- **Editor evaluation (React path) logged** — BlockNote vs Tiptap vs Milkdown vs Yoopta researched in depth. Nathan's call: BlockNote (open-source core); alternatives stay as pivot doors. See `History.md`.

- **SwiftUI editor strategy locked** — two-phase. Phase A: native `TextEditor<AttributedString>` with quick fork to add H4-H6 and toggles; would be implemented in 1-2 days. Phase B: full custom editor with hover-on-selection bubble toolbar (Medium/Notion-style). Segment-based render handles callouts and columns; would be added once the apps core features are solidified. Captured in `// SwiftInfo.md`.

- **Toggles added as v1 Pages feature** — collapsible content blocks (Notion-style). Joins `@Columns` and callouts as the third Page block-level feature; added natively with React editors, would be quickly added during Phase A if Swift.

- **SwiftUI exploration completed** — Interactful clarified as a reference app (not a library). Spaces viable in pure SwiftUI (`visfitness/reorderable` + `stevengharris/SplitView`).

- **Resources.md populated** — library references for both React and SwiftUI paths, plus the editor evaluation links.

---

#### Branch Status

Main branch. Initial commit pushed to `Natertot215/Project-Pommora` (force-pushed, replacing prior history).
