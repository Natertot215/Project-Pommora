### Architecture

Pommora's stack is open between React+Electron and SwiftUI. Whichever ships, the system's *functionalities* — the decisions that define how Pommora behaves — are designed to work across both. If Pommora is ever rebuilt in the other stack, the rebuild is guided translation work, not redesign.

This is **conceptual** portability — the decisions survive a stack pivot. It is NOT structural portability — the codebase isn't pre-arranged for a hot-swap, the same code doesn't render to both UIs, and there's no enforced layer separation that would let someone swap implementations.

---

#### What survives a rebuild

These are the decisions that define Pommora and would carry forward to a rebuild in the other stack:

- **File formats** — Markdown for Pages, `_collection.json` for Collection schemas, `.space.json` for Spaces (block trees), YAML frontmatter shape
- **SQLite schema** — `pages`, `collections`, `spaces`, `links` tables; FTS5 indexing pattern; JSON1 query patterns
- **Domain model** — Pages, Collections, Spaces; their definitions, linking model, membership rules (`// Features//Domain-Model.md`)
- **Property type catalog** — number, checkbox, date, datetime, select, status, multi-select, relation, URL; config shapes; schema mutation rules (`// Features//Properties.md`)
- **Directive syntax** — `:::columns`, `:::callout`, toggles; wikilink syntax; how each parses and renders
- **Wikilink behavior** — name-based resolution, rename cascade, ambiguity disambiguation
- **View directives** — table / board / list / cards / gallery; saved view spec shape; embed-time override semantics
- **Design tokens** — Figma's semantic role-based naming exports cleanly to either CSS custom properties (React) or SwiftUI Color extensions (`// Guidelines//UIX-Guide.md`)
- **UX patterns** — three-pane shell, sidebar logical model, collapsed-by-default disclosure, prose-first editor feel

Whichever stack ships uses these decisions. A rebuild in the other stack re-implements them in the other language; the decisions don't change.

---

#### What doesn't survive

These are inherently stack-locked and would be rewritten in a rebuild:

- The codebase itself (TypeScript ↔ Swift)
- UI framework idioms (React components ↔ SwiftUI views)
- Editor primitive (BlockNote ↔ native `TextEditor` + `AttributedString`)
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
- View specs (filter, sort, group) are data, not code — same files work in both stacks
- File renames + wikilink rewrites are an algorithm specified in the PRD, not a stack-specific code pattern
- The Markdown file is the spec, not the render — directives reference data; data lives in SQLite; rendering is stack-specific but the directives aren't

There is no "Core layer with zero UI imports" rule. There is no enforced three-layer model. Implementation patterns inside whichever stack ships are stack-natural — the portability comes from the documented decisions above, not from how the code is organized.

---

#### Translation-ready documents

These docs describe Pommora in implementation-neutral terms — they don't change for a stack pivot:

- `PommoraPRD.md` — overall architecture, storage model, file rename algorithm
- `// Guidelines//UIX-Guide.md` — token taxonomy, dual-export naming
- `// Features//Properties.md` — property type catalog, schema rules
- `// Features//Domain-Model.md` — Pages / Collections / Spaces definitions
- `// Features//Prospects.md` — wishlist features

Stack-specific implementation references — the maps for either rebuild direction:

- `// ReactInfo.md` — React+Electron deep reference
- `// SwiftInfo.md` — SwiftUI deep reference
- `// Resources.md` — external resources catalog (per-stack sections)
