## Libraries — React Build Catalog

The vetted library menu. Each entry is tagged **Decided** (in `package.json` today), **Candidate** (named, not yet installed), or **Not-yet-needed** (for a deferred phase). Reconcile against `React/package.json` before trusting any version.

### Shell · build · packaging

- **Electron** + **electron-vite** — desktop shell + Vite-first dev loop with main-process HMR. **Decided.**
- **Vite 7** + **@vitejs/plugin-react 5** — renderer bundler. **Decided** (compat pin: newer plugin-react needs Vite 8, unsupported by electron-vite 5).
- **electron-builder** — packaging + (via `electron-updater`) auto-update. **Decided** for packaging; updater **Not-yet-needed**.
- **@electron/rebuild** — native-module ABI rebuild for `better-sqlite3` at package time. **Decided** (used in `npm run package`).
- **@electron/notarize** · **@sentry/electron** — notarization wrapper · crash reporting. **Not-yet-needed** (current build is ad-hoc-signed). See `Distribution.md`.

### UI · styling · icons

- **React 19** + **TypeScript 6** — **Decided.**
- **vanilla-extract** (`@vanilla-extract/css` + vite-plugin) — typed, zero-runtime CSS-in-TS; the token layer authors `*.css.ts`. **Decided.** (Tailwind was the pre-build guess — not used.)
- **lucide-react** — icon set; curated registry in `design-system/symbols/` driven by `Symbols.md`. **Decided.** (Material Symbols + a `symbols.json` indirection layer was the pre-build guess — not used. A user-swappable icon library, incl. SF Symbols, remains a possible future setting.)
- **@fontsource-variable/inter** — the app font. **Decided.**

### State · data · search

- **Zustand 5** (vanilla + `useSyncExternalStore`) — framework-agnostic store. **Decided.**
- **better-sqlite3 12** (WAL) — synchronous SQLite behind `db.ts`; a regeneratable query accelerator, off the read path. **Decided.**
- **zod 4** — schema = codec = type for sidecars + frontmatter. **Decided.** `z.looseObject` defensively retains foreign keys on sidecars — note this is *defensive*, not required: sidecars are controlled schemas, and markdown frontmatter (not the sidecar) is the preserve-everything surface.
- **ulidx** — monotonic ULID ids. **Decided.**
- **write-file-atomic** + **eemeli/yaml** — atomic writes + the comment-preserving YAML Document API. **Decided.**
- **chokidar 5** — filesystem watcher (Phase 4 live refresh). **Decided.** (`@parcel/watcher` is faster on very large trees but adds a native-module rebuild like better-sqlite3 — revisit only if watch perf at nexus scale becomes an issue.)
- **SQLite FTS5** — full-text search; `unicode61` tokenizer with `remove_diacritics=2` + external-content mode over the `pages` table is the nexus-scale pattern (1k–10k pages). `MiniSearch` (in-memory) is fine to ~2k notes but balloons by 10k. **Not-yet-needed** (deferred global search; ships inside better-sqlite3 already).

### Markdown · editor (see `Editor.md`)

- **react-markdown** + **remark-gfm** — read-only page render (Phase 2). **Decided.**
- **CodeMirror 6** — candidate for the core Pages markdown editor (Framework's pick; not installed). But strongly consider building our own — see `Editor.md`. **Candidate.**
- **remark-directive** + **mdast-util-directive** — `:::columns` / `:::callout` round-trip (`directiveToMarkdown()`; nesting needs more colons on the outer fence). **Not-yet-needed.**
- **@flowershow/remark-wiki-link** — Obsidian-flavored `[[wikilinks]]`, `![[embeds]]`; healthiest of the maintained options. **Not-yet-needed.**
- **BlockNote / Tiptap / Milkdown / Yoopta** — block-editor candidates for the deferred Contexts-as-blocks + Homepage frontier. **Not-yet-needed.** See `Editor.md`.

### Drag-and-drop · block layout

- **PommoraDND** — the **in-house drag-and-drop engine** (behind the `interactions/drag.tsx` seam): measure-once, no mid-drag array churn, pointer-capture single sensor, closest-centre + hysteresis, decide-then-animate; constraints, auto-scroll, keyboard + ARIA. **Decided + shipped** — built, reviewed, and Lab-approved (2026-06-18); replaced `@dnd-kit` entirely. Spec → `Features/DragAndDrop.md`.
- **@dnd-kit** — the reference engine PommoraDND was dissected from. **Replaced + uninstalled** (2026-06-18) — no longer a dependency or import. Kept here only as a historical anchor for the dissection.
- **react-grid-layout** — responsive, draggable + resizable **grid** layout with breakpoints; React-only, MIT (`/react-grid-layout/react-grid-layout`). Fits 2-D **dashboard / widget** composition — the Homepage composed-blocks dashboard. Distinct from PommoraDND (which owns linear / nested reorder), not a substitute. **Candidate** — verify React 19 compatibility + maintenance health at adoption time.
