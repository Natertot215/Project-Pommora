### Architecture

Pommora's stack is locked to SwiftUI. The system's *functionalities* — the decisions that define how Pommora behaves — are designed to survive a hypothetical future rebuild in React+Electron if a pivot were ever needed. The rebuild would be guided translation work, not redesign.

This is **conceptual** portability — the decisions survive a stack pivot. It is NOT structural portability — the codebase isn't pre-arranged for a hot-swap, the same code doesn't render to both UIs, and there's no enforced layer separation that would let someone swap implementations.

---

#### What survives a rebuild

These are the decisions that define Pommora and would carry forward to a rebuild in React+Electron:

- **File formats** — Markdown for Pages (inside Pages collections, or loose anywhere outside Collection folders), `_collection.json` for Collection schemas (carries `kind`: `"pages"` | `"items"`), one `.json` per Item (inside an Items collection, or loose), `.space.json` for Spaces (block trees), YAML frontmatter shape
- **Vault structure conventions** — `.pommora//` at vault root holds app config and SQLite index (regeneratable); `.trash//` at vault root holds deleted entities (preserving original relative path; restoration is a file move back); both are leading-dot hidden folders
- **SQLite schema** — `pages`, `items`, `collections`, `spaces`, `links` tables; FTS5 indexing pattern; JSON1 query patterns
- **Domain model** — Pages, Items, Collections (typed at creation: `kind` = `"pages"` or `"items"`), Spaces; their definitions, linking model, membership rules (`// Features//Domain-Model.md`)
- **Property type catalog** — number, checkbox, date, datetime, select, multi-select, relation, URL; config shapes; schema mutation rules. Shared between Pages (values in frontmatter) and Items (values in JSON entry) (`// Features//Properties.md`). No dedicated `Status` type — Status-like properties are just Selects named "Status."
- **Directive syntax** — `:::columns` (multi-column rendering on Pages), `:::callout` (outlined-box callout, distinct from blockquotes); wikilink syntax; how each parses and renders. Blockquotes use standard `>` syntax (no directive; rendered with a filled background and left-side emphasis bar). Headings are foldable by default (built-in UI, not a directive). Pages support these two directives on top of standard Markdown; Spaces have their own block-tree JSON schema separate from Markdown directives.
- **Editor serialization architecture — canonical on-disk format vs rich in-editor working format.** Every editor framework has an internal working representation that isn't its on-disk format. Pommora's design treats this as a load-bearing decision: the on-disk format (Markdown for Pages, JSON for Spaces / Items / Collections) is what agents and external tools see; the in-editor working format is whatever the editor framework prefers (a styled-attribute model on the SwiftUI native editor; the JS editor's internal block tree on WKWebView Option 2). Explicit serializers bridge the two for the Pommora-specific directives. This pattern survives a stack pivot — the on-disk format is canonical regardless of which editor the codebase uses; the in-editor working format is stack-specific by definition.
- **Wikilink behavior** — name-based resolution, rename cascade, ambiguity disambiguation
- **View directives** — table / board / list / cards / gallery; saved view spec shape; embed-time override semantics. Views render members of whichever kind the source Collection is (no per-view member-kind switch — that decision lives at the Collection level).
- **Design tokens** — Figma's semantic role-based naming exports cleanly to SwiftUI Color extensions (and, if pivoted, to CSS custom properties) (`// Guidelines//UIX-Guide.md`)
- **UX patterns** — three-pane shell, sidebar logical model, collapsed-by-default disclosure, wikilinks-as-styled-colored-inline-text, Item window (popover anchored to trigger; Calendar-event-detail pattern). Editor UX is stack-specific and does NOT survive a rebuild: SwiftUI Pages run either a source-with-decorations native text editor (Option 1) or a WKWebView-hosted JS editor — Tiptap, Milkdown, or BlockNote (Option 2, likely direction). On-disk Markdown is identical regardless of editor choice.
- **Agent legibility contract** — every entity is a file an external agent can read directly; SQLite is performance scaffolding, not source of truth. Survives any stack rebuild trivially because the contract is about the on-disk shape, not the runtime.

The SwiftUI implementation uses these decisions. A rebuild in React+Electron would re-implement them in TypeScript; the decisions themselves don't change.

---

#### What doesn't survive

These are inherently stack-locked and would be rewritten in a rebuild:

- The codebase itself (Swift → TypeScript)
- UI framework idioms (SwiftUI views → React components)
- Editor primitive (SwiftUI Option 1: native NSTextView, or Option 2: WKWebView hosting Tiptap / Milkdown / BlockNote → BlockNote or Tiptap on React directly)
- Reactive primitives (`@Observable` + `ValueObservation` → Zustand + hooks)
- Build / packaging tooling (Xcode + SPM → electron-vite + electron-builder)
- File watching (FSEventStream → `@parcel/watcher`)
- SQLite library (GRDB.swift → better-sqlite3)
- Distribution mechanisms (Sparkle → electron-updater)

The React-side detail for each of these lives in `// ReactInfo//` (organized by topic — `Editor.md`, `Spaces-DnD.md`, `StateData.md`, `MacIntegration.md`, `Distribution.md`, `Styling-Tokens.md`, `Symbols-guide.md`). Pivot methodology lives in `// ReactInfo//Contingency.md`.

---

#### Practical discipline (not enforcement)

These aren't enforced separations or structural rules — they're patterns that keep a future rebuild scenario tractable:

- Frontmatter schemas live in JSON sidecars (canonical files), not embedded in code, so a rebuild loads the same schemas
- Item entries live as individual `.json` files (canonical files), not in SQLite-only rows — so a rebuild reads them with `JSONDecoder` / `JSON.parse` and gets the same data
- View specs (filter, sort, group, shown-properties) are data, not code — same files work in both stacks
- File renames + wikilink rewrites are an algorithm specified in the PRD, not a stack-specific code pattern
- The Markdown file is the spec, not the render — directives reference data; data lives in SQLite; rendering is stack-specific but the directives aren't
- The agent-legibility contract is a discipline applied to every architecture decision: would an external agent reading files-only still see this? If no, the decision needs revisiting.

There is no "Core layer with zero UI imports" rule. There is no enforced three-layer model. Implementation patterns are SwiftUI-natural — the portability comes from the documented decisions above, not from how the code is organized.

---

#### What Pommora explicitly does not own

Some adjacent concerns are intentionally left to OS-level tools rather than built into Pommora:

- **Versioning / file history.** Pommora handles in-session undo (free from the editor). Long-term history is the user's responsibility via Time Machine, git on the vault folder, or filesystem snapshots. Pommora does not maintain an internal version store or auto-commit on save. This keeps the vault clean and avoids duplicating what the OS already does well.
- **Cross-device sync (for v1).** The vault is user-pickable on first launch, so a user can place it in iCloud Drive / Dropbox / a synced folder and get device-to-device sync for free. Real cloud sync (Supabase or similar) is a real long-term Prospect, but v1 leans on filesystem sync.
- **Backup.** Same as versioning — Time Machine and friends.

---

#### Reference

Implementation-neutral specs (don't change for a stack pivot): `PommoraPRD.md`, `// Features//Domain-Model.md`, `// Features//Properties.md`, `// Features//Prospects.md`, `// Guidelines//UIX-Guide.md`.

React-side reference for a hypothetical pivot: `// ReactInfo//` folder, with `Contingency.md` as the entry point for translation methodology.
