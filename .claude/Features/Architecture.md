### Architecture

Pommora's stack is locked to SwiftUI. The system's *functionalities* — the decisions that define how Pommora behaves — are designed to survive a hypothetical future rebuild in React+Electron if a pivot were ever needed. The rebuild would be guided translation work, not redesign.

This is **conceptual** portability — the decisions survive a stack pivot. It is NOT structural portability — the codebase isn't pre-arranged for a hot-swap, the same code doesn't render to both UIs, and there's no enforced layer separation that would let someone swap implementations.

---

#### What survives a rebuild

These are the decisions that define Pommora and would carry forward to a rebuild in React+Electron:

- **File formats** — Markdown for Pages, `.json` for Items, `.space.json` for Spaces (tier-1 Contexts), folder + `_topic.json` for Topics (tier-2 Contexts) with `.subtopic.json` files inside for tier 3, `_vault.json` for Vaults, `.agenda.json` for Agenda items, `.nexus/homepage.json` for the singleton Homepage, YAML frontmatter shape on Pages
- **Nexus structure conventions** — `.nexus//` at nexus root holds app config + SQLite index (regeneratable) + Contexts files + Homepage; user-visible Vaults and Agenda folder live at nexus root; `.trash//` at nexus root holds deleted entities (preserving original relative path); leading-dot folders are hidden in the sidebar
- **SQLite schema** — `pages`, `items`, `agenda`, `tiers` (Contexts), `vaults`, `links` tables; FTS5 indexing pattern; JSON1 query patterns
- **Domain model** — 2-layer model with PARA-aligned naming: Contexts (Spaces tier 1 / Topics tier 2 / Sub-topics tier 3) in the organization layer; Vaults + Collections + Content (Pages + Items) and Agenda in the operational layer; Homepage as singleton dashboard (`// Features//Domain-Model.md`)
- **Tier system** — three-tier Contexts with multi-parent across tiers, single-parent at file for Sub-topics, no same-tier file-structural links; `linked_relations` as typed multi-valued relation property on Sub-topics; tier names user-configurable per-Nexus (Capacities-style singular + plural in `.nexus/tier-config.json`)
- **Property type catalog** — number, checkbox, date, datetime, select, multi-select, relation, URL; config shapes; schema mutation rules. Shared between Pages (frontmatter), Items (`.json` properties), and Agenda items (`.agenda.json` properties); Vault schema is Vault-wide in v1 (`// Features//Properties.md`). No dedicated `Status` type — Status-like properties are just Selects named "Status." **Relation values use the tagged-object encoding `{"$rel": "<ULID>"}`** (paradigm decision 2026-05-16) so external agents can identify relation edges without consulting Vault schema.
- **Directive syntax** — `:::columns` (multi-column rendering on Pages), `:::callout` (outlined-box callout, distinct from blockquotes); wikilink syntax. Blockquotes use standard `>` syntax (rendered with filled background and left-side emphasis bar). Headings are foldable by default. Pages support these two directives on top of standard Markdown; Contexts + Homepage use a separate block-tree JSON schema.
- **Editor serialization architecture — canonical on-disk format vs rich in-editor working format.** On-disk format (Markdown for Pages, JSON for everything else) is what agents see; in-editor working format is whatever the framework prefers. Explicit serializers bridge them for the Pommora-specific directives.
- **Inline-editing principle** — every embedded view inside a composed-blocks surface (Context page, Homepage) is a live, fully-editable view of its source. Edits route through the source entity's manager → atomic write → file watcher → SQLite re-index → all embedded views refresh. NOT a read-only snapshot. Full inline editing of a referenced Page's body (Notion synced blocks) is post-v1 (`// Features//Prospects.md`).
- **Wikilink behavior** — name-based resolution, rename cascade, ambiguity disambiguation
- **View directives** — table / board / list / cards / gallery; saved view spec shape; embed-time override semantics
- **EventKit integration contract** — Agenda items map to `EKEvent` / `EKReminder` based on which time fields are populated; sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys required; modern `requestFullAccessTo*` APIs used
- **Design values** — Pommora-brand accent / code / callout / blockquote values live in `Assets.xcassets` + `Color+Pommora.swift` / `Font+Pommora.swift`. SwiftUI semantic colors and Font scale carry the rest. (`// Guidelines//UIX-Guide.md` covers Swift-side conventions.)
- **UX patterns** — three-pane shell, four-group sidebar (heading-less pinned section at top + Spaces / Topics / Vaults), collapsed-by-default disclosure, wikilinks-as-styled-colored-inline-text, Item Window (popover anchored to trigger; Calendar-event-detail pattern), right-click context menus as the canonical creation affordance (scoped by cursor location — no always-visible "+ New" buttons in the sidebar), Pages-in-sidebar / Items-and-Agenda-only-in-detail-pane split. Editor UX is stack-specific and does NOT survive a rebuild.
- **Agent legibility contract** — every entity is a file an external agent can read directly; SQLite is performance scaffolding, not source of truth.

The SwiftUI implementation uses these decisions. A rebuild in React+Electron would re-implement them in TypeScript; the decisions themselves don't change.

---

#### What doesn't survive

These are inherently stack-locked and would be rewritten in a rebuild:

- The codebase itself (Swift → TypeScript)
- UI framework idioms (SwiftUI views → React components)
- Editor primitive (SwiftUI Option 1: native NSTextView + `swift-markdown` + TextKit 2, or Option 2: WKWebView hosting Tiptap / Milkdown / BlockNote → BlockNote or Tiptap on React directly)
- Reactive primitives (`@Observable` + `ValueObservation` → Zustand + hooks)
- Build / packaging tooling (Xcode + SPM → electron-vite + electron-builder)
- File watching (FSEventStream → `@parcel/watcher`)
- SQLite library (GRDB.swift → better-sqlite3)
- Distribution mechanisms (Sparkle → electron-updater)

The React-side detail for each of these lives in `// ReactInfo//` (organized by topic — `Editor.md`, `Spaces-DnD.md`, `StateData.md`, `MacIntegration.md`, `Distribution.md`, `Styling-Tokens.md`, `Symbols-guide.md`). Pivot methodology lives in `// ReactInfo//Contingency.md`.

---

#### Practical discipline (not enforcement)

These aren't enforced separations or structural rules — they're patterns that keep a future rebuild scenario tractable:

- Frontmatter schemas live in JSON sidecars (canonical files), not embedded in code, so a rebuild loads the same schemas.
- Item entries live as individual `.json` files (canonical files), not in SQLite-only rows — a rebuild reads them with `JSONDecoder` and gets the same data.
- View specs (filter, sort, group, shown-properties) are data, not code — the same files would be consumed identically by a React rebuild.
- File renames + wikilink rewrites are an algorithm specified in the PRD, not a code-shape pattern.
- The Markdown file is the spec, not the render — directives reference data; data lives in SQLite; rendering depends on the editor implementation but the directives don't.
- The agent-legibility contract is a discipline applied to every architecture decision: would an external agent reading files-only still see this? If no, the decision needs revisiting.

There is no enforced layer separation — no "Core layer with zero UI imports" rule, no three-tier model. Implementation patterns are SwiftUI-natural; portability comes from the documented decisions above, not from how the code is organized.

---

#### What Pommora explicitly does not own

Some adjacent concerns are intentionally left to OS-level tools rather than built into Pommora:

- **Versioning / file history.** Pommora handles in-session undo (free from the editor). Long-term history is the user's responsibility via Time Machine, git on the nexus folder, or filesystem snapshots. Pommora does not maintain an internal version store or auto-commit on save. This keeps the nexus clean and avoids duplicating what the OS already does well.
- **Cross-device sync (for v1).** The nexus is user-pickable on first launch, so a user can place it in iCloud Drive / Dropbox / a synced folder and get device-to-device sync for free. Real cloud sync (Supabase or similar) is a real long-term Prospect, but v1 leans on filesystem sync.
- **Backup.** Same as versioning — Time Machine and friends.

---

#### Reference

Implementation-neutral specs (don't change for a stack pivot): `PommoraPRD.md`, `// Features//Domain-Model.md`, `// Features//Properties.md`, `// Features//Prospects.md`, `// Guidelines//UIX-Guide.md`.

React-side reference for a hypothetical pivot: `// ReactInfo//` folder, with `Contingency.md` as the entry point for translation methodology.
