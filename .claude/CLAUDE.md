### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. Three top-level entities — **Pages** (Markdown documents), **Collections** (folder + `_collection.json` schema sidecar), **Spaces** (Notion-page-style block-composed surfaces) — plus **Items** (`.json`, Collection-bound row-shaped). Collections are typed at creation (`kind: "pages" | "items"`). SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source. Stack portability across React+Electron and SwiftUI is the load-bearing constraint.

#### Working with Nathan

- Non-coder, first agentic project. Nathan directs, Claude implements. Nathan does not write code.
- Mac user, always Mac. Lives in the Apple ecosystem.
- Values cohesion and simplicity over ecosystem reach or feature ceilings.
- Push back honestly when direction is unclear or a mistake is forming.
- Vocabulary may be imprecise — clarify before assuming.
- Studio-resident project; the Studio CLAUDE.md global rules and Nathan's NathanOS rules apply.

#### Stack — Under Active Evaluation

Two viable paths: **React + Electron** or **SwiftUI**. Both produce identical on-disk Markdown and identical SQLite indexes; they differ in the editor surface and desktop shell. Full dual-stack table in `PommoraPRD.md`. The decision is deferred. Documentation across the project is written stack-agnostic at the capability level; only `// Planning//v0.0.md` is stack-locked (currently React+Electron) and gets rewritten if SwiftUI is chosen.

#### Core Principles

- **Three load-bearing constraints:** (1) **stack portability of functionalities** — file formats, schemas, design tokens, UX patterns survive a stack rebuild; (2) **cross-vault queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Pages = `.md`. Collections = folder + `_collection.json` (carries the Collection's `kind`). Items = individual `.json` files (one per Item; filename = title); members live inside Items collections, loose Items live anywhere else. Spaces = `.space.json` block trees in `.pommora// spaces//`. Loose Pages and loose Items both exist; carry only built-in fields. SQLite is regeneratable index — no user data trapped in it.

- **Filename = title** everywhere. No `title` field; no `name` field on Items. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Spaces are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes). Standard Markdown handles tables (GFM), blockquotes (standard `>` syntax, rendered with a filled background + left-side emphasis bar), dividers (`---`), and everything else. Headings are foldable by default (built-in UI, not a directive). **"Block-level features" as a project term belongs to Spaces only** — Spaces are the page-like canvases with drag-and-drop blocks.

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips. Both stacks.

- **Relations stored by ID, displayed by title.** Frontmatter relation properties hold the target's ID (rename-safe); the editor renders the target's current title as styled colored inline text.

- **Move-strip rule.** Moving a member across Collections (or in/out of loose state) strips properties not in the destination schema — Notion-style; no quarantine.

- **Design system lives in Figma; components live in `// UI-UX//Components//`** (which hosts Pommora's own localhost dev server on the React path; SwiftUI views browsed via Xcode `#Preview` on the Swift path). Two-tier source of truth: Figma owns design tokens (semantic role-based names: `surface// primary// bg`); the component library owns components built from them. Designs flow Figma → component library directly — **no Storybook intermediary**. Same Figma source exports to CSS custom properties (React) and SwiftUI Color extensions. Detail → `// UI-UX//UI-UX.md`; build brief → `.claude// Planning//Figma Prompt.md`.

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.

#### Document Map

- `PommoraPRD.md` — high-level product requirements and architecture (includes the dual-stack table)
- `Handoff.md` — current state and near-term priorities (read first at session start)
- `History.md` — locked decisions, brief
- `Framework.md` — phased roadmap to v1.0
- `Resources.md` — external resources catalog, organized by stack
- `ReactInfo.md` — React+Electron implementation reference
- `SwiftInfo.md` — SwiftUI implementation reference (parallel structure to ReactInfo)
- `// Features//`
  - `Domain-Model.md` — entity overview, linking, sidebar, resolved decisions
  - `Pages.md` — on-disk shape, Markdown features + two rendering directives, editor surface, wikilinks
  - `Collections.md` — typed-Collection semantics, `_collection.json` schema, view types, loose entities, embedded views
  - `Items.md` — brief: row-shaped `.json` entries; on-disk, capabilities, kind-picking guidance
  - `Spaces.md` — `.space.json` schema, drag-and-drop canvas, block types, referential framing
  - `Architecture.md` — what survives a stack rebuild (conceptual portability)
  - `Properties.md` — property type catalog (shared between Pages and Items)
  - `Prospects.md` — post-v1 features and brainstormed ideas
- `// Planning//`
  - `v0.0.md` — current build spec (React+Electron-locked)
  - `Figma Prompt.md` — design-system build brief (pasteable into a fresh session with `/figma-use`)
- `// Guidelines//`
  - `UIX-Guide.md` — Figma source-of-truth, dual-export naming, tier model
  - `Symbols-guide.md` — React-only: semantic symbol roles + `.pommora// symbols.json` mapping for library swap

##### Project root (outside `.claude//`)

- `// UI-UX//` — design system home. Contains design materials (`Design//`) and the component library (`Components//`, which hosts the React localhost). Guidelines: `UI-UX//UI-UX.md`, `UI-UX//Design//Design Guidelines.md`, `UI-UX//Components//Component Guidelines.md`. Stack-shared layout.

#### Stack-conditional content convention

Shared docs use a labeling convention so the two stack paths don't blur:

- Agnostic content first (the "what" / "why" true regardless of stack)
- Where divergence exists: paragraph break, then `**For React**` (bold marker on its own line) with content underneath. Then `**For Swift**` (bold marker on its own line) with content underneath.
- React first, Swift second.
- Use only the label(s) needed.

**Exceptions:** comparison tables (PRD dual-stack table) speak for themselves; catalog docs (`Resources.md`) use per-stack headings; stack-locked specs (`Planning/v0.0.md`, `SwiftInfo.md`, `ReactInfo.md`) don't need labels. Compact one-line principles may use parenthetical stack mentions instead.

#### Active Version

**v0.0** — App launches into a styled three-pane shell consuming design tokens. No editor, no data wiring. Spec at `// Planning//v0.0.md`. **Implementation is gated on the stack decision.**
