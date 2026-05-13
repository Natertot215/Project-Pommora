### React Implementation Reference — Folder Index

Topic-based reference for the React+Electron implementation path. **SwiftUI is Pommora's locked stack.** This folder preserves React knowledge for two purposes: (1) noting "obvious React way" alongside Swift implementation work as it lands, and (2) staying ready if a future pivot ever becomes necessary.

For pivot methodology and translation patterns, see `Contingency.md`. For the obligation to update files in this folder during Swift work, see Contingency's "Update obligation" section.

#### Files

- `Contingency.md` — Translation methodology and the update-obligation pattern
- `Editor.md` — BlockNote / Tiptap, two-format serialization (Markdown + JSON), custom serializers for the two directives, wikilink rendering
- `Spaces-DnD.md` — `@dnd-kit/core` v6 + flat-array tree representation, atomic block write discipline
- `Styling-Tokens.md` — Tailwind v4 + CSS custom properties exported from Figma, dual-export naming
- `StateData.md` — Zustand vanilla + `useSyncExternalStore`, table-keyed pub/sub for `better-sqlite3` reactivity, `@parcel/watcher` v2.5+ gotchas, FTS5 `unicode61` patterns
- `MacIntegration.md` — Pure-Electron first-party areas, companion-bundle territory, hard ceilings
- `Distribution.md` — electron-vite + electron-builder, code signing + notarization, MAS sandbox, auto-update via electron-updater
- `Symbols-guide.md` — Semantic symbol roles + `.pommora// symbols.json` mapping for library swap (React-only — SwiftUI uses SF Symbols natively)
- `Resources.md` — React-side library catalog
- `v0.0.md` — Preserved React+Electron-locked v0.0 spec (superseded by the SwiftUI v0.0 spec when authored)

#### Origin

The contents of these files were sliced from the previous monolithic `.claude//ReactInfo.md` (~20K) plus `**For React**` blocks extracted from main docs during the Swift-lock restructure. Original session work and research findings are preserved verbatim where they survive a slice; nothing is paraphrased away.

---

#### Verified findings (preserved from prior research)

- **BlockNote (MPL-2.0) and Tiptap (MIT)** are co-primary editor candidates; both deliver the Notion-style block editor surface on top of continuous Markdown on disk. Detail → `Editor.md`.
- **`@dnd-kit/core` v6.x** for Spaces composer. **NOT** `@dnd-kit/react` (v0.x, pre-1.0). Detail → `Spaces-DnD.md`.
- **`@parcel/watcher` v2.5+** for vault folder watching — native FSEvents on macOS, materially faster than chokidar at large tree scale. Detail → `StateData.md`.
- **`better-sqlite3` (WAL mode) + SQLite FTS5** for the local index. Detail → `StateData.md`.
- **`remark-directive` + `mdast-util-directive`** for `:::columns` and `:::callout`. Nesting requires outer fence to use more colons (`::::columns` containing `:::callout`). Detail → `Editor.md`.
- **`@flowershow/remark-wiki-link` v3.3.1+** for Obsidian-flavored wikilinks. Detail → `Editor.md`.