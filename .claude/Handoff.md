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

- **Spike before commit (optional)** — if the stack call wants empirical validation before locking: spike BlockNote markdown round-trip with a custom serializer for `:::columns`, OR spike SwiftUI `TextEditor` segment-based render to size the cross-segment cursor problem. Either spike is bounded (a couple of focused sessions); neither is required.

---

#### Open Questions

- **Stack:** React+Electron or SwiftUI?
- **License:** what does Pommora ship under?

---

#### Branch Status

Main branch only. Initial commit pushed to `Natertot215/Project-Pommora`.
