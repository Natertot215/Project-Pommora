### Architecture

Pommora's stack is open between React+Electron and SwiftUI. Whichever ships, the system's *functionalities* — the decisions that define how Pommora behaves — are designed to work across both. If Pommora is ever rebuilt in the other stack, the rebuild is guided translation work, not redesign.

This is **conceptual** portability — the decisions survive a stack pivot. It is NOT structural portability — the codebase isn't pre-arranged for a hot-swap, the same code doesn't render to both UIs, and there's no enforced layer separation that would let someone swap implementations.

---

#### What survives a rebuild

These are the decisions that define Pommora and would carry forward to a rebuild in the other stack:

- **File formats** — Markdown for Pages (inside Pages collections, or loose anywhere outside Collection folders), `_collection.json` for Collection schemas (carries `kind`: `"pages"` | `"items"`), one `.json` per Item (inside an Items collection, or loose), `.space.json` for Spaces (block trees), YAML frontmatter shape
- **Vault structure conventions** — `.pommora//` at vault root holds app config and SQLite index (regeneratable); `.trash//` at vault root holds deleted entities (preserving original relative path; restoration is a file move back); both are leading-dot hidden folders
- **SQLite schema** — `pages`, `items`, `collections`, `spaces`, `links` tables; FTS5 indexing pattern; JSON1 query patterns
- **Domain model** — Pages, Items, Collections (typed at creation: `kind` = `"pages"` or `"items"`), Spaces; their definitions, linking model, membership rules (`// Features//Domain-Model.md`)
- **Property type catalog** — number, checkbox, date, datetime, select, multi-select, relation, URL; config shapes; schema mutation rules. Shared between Pages (values in frontmatter) and Items (values in JSON entry) (`// Features//Properties.md`). No dedicated `Status` type — Status-like properties are just Selects named "Status."
- **Directive syntax** — `:::columns` (multi-column rendering on Pages), `:::callout` (outlined-box callout, distinct from blockquotes); wikilink syntax; how each parses and renders. Blockquotes use standard `>` syntax (no directive; rendered with a filled background and left-side emphasis bar). Headings are foldable by default (built-in UI, not a directive). Pages support these two directives on top of standard Markdown; Spaces have their own block-tree JSON schema separate from Markdown directives.
- **Editor serialization architecture — canonical on-disk format vs rich in-editor working format.** Every editor framework has an internal working representation that isn't its on-disk format. Pommora's design treats this as a load-bearing decision: the on-disk format (Markdown for Pages, JSON for Spaces / Items / Collections) is what agents and external tools see; the in-editor working format is whatever the editor framework prefers (a structured block tree on the React side; a styled-attribute model on the SwiftUI side). Explicit serializers bridge the two for the Pommora-specific directives. This pattern survives a stack pivot — the on-disk format is canonical regardless of which editor the codebase uses; the in-editor working format is stack-specific by definition.
- **Wikilink behavior** — name-based resolution, rename cascade, ambiguity disambiguation
- **View directives** — table / board / list / cards / gallery; saved view spec shape; embed-time override semantics. Views render members of whichever kind the source Collection is (no per-view member-kind switch — that decision lives at the Collection level).
- **Design tokens** — Figma's semantic role-based naming exports cleanly to either CSS custom properties (React) or SwiftUI Color extensions (`// Guidelines//UIX-Guide.md`)
- **UX patterns** — three-pane shell, sidebar logical model, collapsed-by-default disclosure, wikilinks-as-styled-colored-inline-text, Item window (popover anchored to trigger; Calendar-event-detail pattern). (Editor UX itself is stack-specific and does NOT survive a rebuild: React Pages run a Notion-style block editor with per-paragraph `+` / drag-handle markers; SwiftUI Pages run either a source-with-decorations native text editor (Option 1) or a WKWebView-hosted JS editor — Tiptap, Milkdown, or BlockNote (Option 2, likely direction). All paths write the same Markdown on disk.)
- **Agent legibility contract** — every entity is a file an external agent can read directly; SQLite is performance scaffolding, not source of truth. Survives any stack rebuild trivially because the contract is about the on-disk shape, not the runtime.

Whichever stack ships uses these decisions. A rebuild in the other stack re-implements them in the other language; the decisions don't change.

---

#### What doesn't survive

These are inherently stack-locked and would be rewritten in a rebuild:

- The codebase itself (TypeScript ↔ Swift)
- UI framework idioms (React components ↔ SwiftUI views)
- Editor primitive (BlockNote or Tiptap on React ↔ SwiftUI Option 1: native markdown editor — fork Clearly or original build; or Option 2: WKWebView hosting Tiptap / Milkdown / BlockNote — likely direction)
- Reactive primitives (Zustand + hooks ↔ `@Observable` + `ValueObservation`)
- Build / packaging tooling (electron-vite + electron-builder ↔ Xcode + SPM)
- File watching (`@parcel/watcher` ↔ FSEventStream)
- SQLite library (better-sqlite3 ↔ GRDB.swift)
- Distribution mechanisms (electron-updater ↔ Sparkle)

These are documented per stack in `// ReactInfo.md` and `// SwiftInfo.md`. When one stack ships, the other doc is the reference for what a future rebuild would target.

---

#### Practical discipline (not enforcement)

These aren't enforced separations or structural rules — they're patterns that keep a future rebuild scenario tractable:

- Frontmatter schemas live in JSON sidecars (canonical files), not embedded in code, so a rebuild loads the same schemas
- Item entries live as individual `.json` files (canonical files), not in SQLite-only rows — so a rebuild reads them with `JSON.parse` / `JSONDecoder` and gets the same data
- View specs (filter, sort, group, shown-properties) are data, not code — same files work in both stacks
- File renames + wikilink rewrites are an algorithm specified in the PRD, not a stack-specific code pattern
- The Markdown file is the spec, not the render — directives reference data; data lives in SQLite; rendering is stack-specific but the directives aren't
- The agent-legibility contract is a discipline applied to every architecture decision: would an external agent reading files-only still see this? If no, the decision needs revisiting.

There is no "Core layer with zero UI imports" rule. There is no enforced three-layer model. Implementation patterns inside whichever stack ships are stack-natural — the portability comes from the documented decisions above, not from how the code is organized.

---

#### What Pommora explicitly does not own

Some adjacent concerns are intentionally left to OS-level tools rather than built into Pommora:

- **Versioning / file history.** Pommora handles in-session undo (free from the editor). Long-term history is the user's responsibility via Time Machine, git on the vault folder, or filesystem snapshots. Pommora does not maintain an internal version store or auto-commit on save. This keeps the vault clean and avoids duplicating what the OS already does well.
- **Cross-device sync (for v1).** The vault is user-pickable on first launch, so a user can place it in iCloud Drive / Dropbox / a synced folder and get device-to-device sync for free. Real cloud sync (Supabase or similar) is a real long-term Prospect, but v1 leans on filesystem sync.
- **Backup.** Same as versioning — Time Machine and friends.

---

#### Reference

Implementation-neutral specs (don't change for a stack pivot): `PommoraPRD.md`, `// Features//Domain-Model.md`, `// Features//Properties.md`, `// Features//Prospects.md`, `// Guidelines//UIX-Guide.md`.

Stack-specific maps for either rebuild direction: `// ReactInfo.md`, `// SwiftInfo.md`, `// Resources.md`.
