### Architecture

Pommora's stack is locked to SwiftUI. The system's *functionalities* — the decisions defining how Pommora behaves — are designed to survive a hypothetical rebuild in React+Electron as translation work, not redesign.

This is **conceptual** portability, NOT structural — the codebase isn't pre-arranged for hot-swap, and there's no enforced layer separation.

---

#### What survives a rebuild

These are the decisions that define Pommora and would carry forward to a rebuild in React+Electron:

- **File formats** — Markdown for Pages, `.json` for Items, `.space.json` for Spaces (tier-1 Contexts), folder + `_topic.json` for Topics (tier-2 Contexts) with `.subtopic.json` files inside for tier 3, `_vault.json` for Vaults, `.agenda.json` for Agenda items, `.nexus/homepage.json` for the singleton Homepage, YAML frontmatter shape on Pages
- **Nexus structure conventions** — `.nexus//` at nexus root holds app config + SQLite index (regeneratable) + Contexts files + Homepage; user-visible Vaults and Agenda folder live at nexus root; `.trash//` at nexus root holds deleted entities (preserving original relative path); leading-dot folders are hidden in the sidebar
- **SQLite schema** — `pages`, `items`, `agenda`, `tiers` (Contexts), `vaults`, `links` tables; FTS5 indexing pattern; JSON1 query patterns
- **Domain model** — 2-layer model with PARA-aligned naming: Contexts (Spaces tier 1 / Topics tier 2 / Sub-topics tier 3) in the organization layer; Vaults + Collections + Content (Pages + Items) and Agenda in the operational layer; Homepage as singleton dashboard (`// Features//Domain-Model.md`)
- **Tier system** — three-tier Contexts with multi-parent across tiers, single-parent at file for Sub-topics, no same-tier file-structural links; `linked_relations` as typed multi-valued relation property on Sub-topics; tier names user-configurable per-Nexus (Capacities-style singular + plural in `.nexus/tier-config.json`)
- **Property type catalog** — 10 types in v0.3.0: number, checkbox, date, date & time, select, multi-select, URL, relation, **status**, last edited time. Config shapes + schema mutation rules. Shared between Pages (frontmatter), Items (`.json` properties), and Agenda items (`.agenda.json` properties); Vault schema is Vault-wide in v1 (`// Features//Properties.md`). **Status is a first-class type** with 3 EventKit-aligned structural groups (Upcoming / In Progress / Done). **Relation values use the tagged-object encoding `{"$rel": "<ULID>"}`** (paradigm decision 2026-05-16) so external agents can identify relation edges without consulting Vault schema.
- **Directive syntax** — `:::columns` (multi-column rendering on Pages), `:::callout` (outlined-box callout, distinct from blockquotes); wikilink syntax. Blockquotes use standard `>` syntax (rendered with filled background and left-side emphasis bar). Headings are foldable by default. Pages support these two directives on top of standard Markdown; Contexts + Homepage use a separate block-tree JSON schema.
- **Editor serialization architecture — canonical on-disk format vs rich in-editor working format.** On-disk format (Markdown for Pages, JSON for everything else) is what agents see; in-editor working format is whatever the framework prefers. Explicit serializers bridge them for the Pommora-specific directives.
- **Inline-editing principle** — every embedded view inside a composed-blocks surface (Context page, Homepage) is a live, fully-editable view of its source. Edits route through the source entity's manager → atomic write → file watcher → SQLite re-index → all embedded views refresh. NOT a read-only snapshot. Full inline editing of a referenced Page's body (Notion synced blocks) is post-v1 (`// Features//Prospects.md`).
- **Wikilink behavior** — name-based resolution, rename cascade, ambiguity disambiguation
- **View directives** — table / board / list / cards / gallery; saved view spec shape; embed-time override semantics
- **EventKit integration contract** — Agenda items map to `EKEvent` / `EKReminder` based on which time fields are populated; sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys required; modern `requestFullAccessTo*` APIs used
- **Design values** — Pommora-brand accent / code / callout / blockquote values live in `Assets.xcassets` + `Color+Pommora.swift` / `Font+Pommora.swift`. SwiftUI semantic colors and Font scale carry the rest. (`// Guidelines//Design.md` covers Swift-side conventions; SF Symbol assignments → `// Guidelines//Symbols.md`.)
- **UX patterns** — three-pane shell, four-group sidebar (heading-less pinned section at top + Spaces / Topics / Vaults), collapsed-by-default disclosure, wikilinks-as-styled-colored-inline-text, Item Window (popover anchored to trigger; Calendar-event-detail pattern), right-click context menus as the canonical creation affordance (scoped by cursor location — no always-visible "+ New" buttons in the sidebar), Pages-in-sidebar / Items-and-Agenda-only-in-detail-pane split. Editor UX is stack-specific and does NOT survive a rebuild.
- **Agent legibility contract** — every entity is a file an external agent can read directly; SQLite is performance scaffolding, not source of truth.

A React+Electron rebuild would re-implement these in TypeScript; the decisions don't change.

---

#### What doesn't survive

These are inherently stack-locked and would be rewritten in a rebuild:

- The codebase itself (Swift → TypeScript)
- UI framework idioms (SwiftUI views → React components)
- Editor primitive (shipped on native NSTextView + Apple `swift-markdown` + vendored `swift-markdown-engine` on TextKit 2; would translate to BlockNote or Tiptap on a React rebuild)
- Reactive primitives (`@Observable` + `ValueObservation` → Zustand + hooks)
- Build / packaging tooling (Xcode + SPM → electron-vite + electron-builder)
- File watching (FSEventStream → `@parcel/watcher`)
- SQLite library (GRDB.swift → better-sqlite3)
- Distribution mechanisms (Sparkle → electron-updater)

The React-side detail for each of these lives in `// ReactInfo//` (organized by topic — `Editor.md`, `Spaces-DnD.md`, `StateData.md`, `MacIntegration.md`, `Distribution.md`, `Styling-Tokens.md`, `Symbols-guide.md`). Pivot methodology lives in `// ReactInfo//Contingency.md`.

---

#### Practical discipline (not enforcement)

Patterns that keep a future rebuild tractable — not enforced rules:

- Frontmatter schemas in JSON sidecars (canonical), not code — rebuild loads same schemas.
- Item entries as individual `.json` files, not SQLite-only — rebuild reads via `JSONDecoder`.
- View specs (filter / sort / group / shown-properties) are data, consumed identically by a React rebuild.
- File renames + wikilink rewrites are PRD-specified algorithm, not a code shape.
- The Markdown file is the spec, not the render — directives reference data; rendering is editor-implementation-dependent.
- Agent-legibility contract applied per decision: would an external file-only agent still see this? If no, revisit.

No enforced layer separation, no "Core layer with zero UI imports" rule. Portability comes from documented decisions, not code organization.

---

#### What Pommora explicitly does not own

Adjacent concerns left to OS-level tools:

- **Versioning / file history.** In-session undo is free from the editor; long-term history is Time Machine, git on the nexus folder, or filesystem snapshots. No internal version store, no auto-commit.
- **Cross-device sync (v1).** Nexus is user-pickable — place in iCloud Drive / Dropbox / synced folder for device-to-device sync. Real cloud sync is a long-term Prospect.
- **Backup.** Same as versioning — Time Machine and friends.

---

#### Reference

Implementation-neutral specs (don't change for a stack pivot): `PommoraPRD.md`, `// Features//Domain-Model.md`, `// Features//Properties.md`, `// Features//Prospects.md`, `// Guidelines//Design.md`, `// Guidelines//Symbols.md`.

React-side reference for a hypothetical pivot: `// ReactInfo//` folder, with `Contingency.md` as the entry point for translation methodology.
