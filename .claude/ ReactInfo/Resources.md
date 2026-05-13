### React-side Library Catalog

Sliced from `.claude//Resources.md` during the Swift-lock restructure. Editor primitives that are co-evaluated for both stacks (BlockNote, Tiptap, Milkdown, etc.) are duplicated here for navigation convenience — the Swift-side catalog also references them under WKWebView Option 2.

---

#### Shell, build, distribution

- **Electron** — desktop shell. [Docs](https://www.electronjs.org/docs/latest)

- **electron-vite** — Vite-first dev experience with HMR for the main process. Pairs with electron-builder for packaging; cleanest dev loop of the React tooling options. [Docs](https://electron-vite.org/)

- **Electron Forge 7+** — alternative all-in-one tool, official + maintained by the Electron team; first-party features (ASAR integrity, universal builds, code signing, notarytool) land here first. [Docs](https://www.electronforge.io/)

- **electron-builder** — packaging + bundled `electron-updater` for auto-update. [Docs](https://www.electron.build/) · [Auto-update](https://www.electron.build/auto-update.html)

- **@electron/rebuild** — native module rebuild for ABI compatibility (better-sqlite3). [GitHub](https://github.com/electron/rebuild)

- **@electron/notarize** — wraps Apple's `notarytool` (post-altool deprecation). [GitHub](https://github.com/electron/notarize)

- **Sentry-Electron** — crash reporting (Crashpad-backed; covers main/renderer/utility processes). [Docs](https://docs.sentry.io/platforms/javascript/guides/electron/)
- **Vite** — bundler / dev server. [Docs](https://vitejs.dev/)

#### UI, styling, components

- **React** — UI framework. [Docs](https://react.dev/)
- **TypeScript** — strict mode. [Docs](https://www.typescriptlang.org/docs/)

- **Tailwind CSS v4** — styling, with CSS custom properties from the design system. [Docs](https://tailwindcss.com/docs)

- **Figma Code Connect** — link Figma components to real component code. [Docs](https://www.figma.com/code-connect-docs/)

(No Storybook — Pommora uses its own localhost dev server for component preview / iteration; designs flow Figma → Pommora localhost directly.)

- **react-material-symbols** — icon delivery. [npm](https://www.npmjs.com/package/react-material-symbols)

#### State, data, search

- **better-sqlite3** — SQLite for Node.js (WAL mode). [GitHub](https://github.com/WiseLibs/better-sqlite3)

- **SQLite FTS5** — full-text search. External-content mode + `unicode61` tokenizer (with `remove_diacritics=2`) is the recommended pattern for vault-scale (1k–10k pages). [SQLite docs](https://www.sqlite.org/fts5.html)

- **Zustand v5+** — state management; `zustand/vanilla` produces a framework-agnostic store that React binds via `useSyncExternalStore`. Conceptually translatable to `@Observable` + `ValueObservation` on a future Swift rebuild. Cleaner fit than Jotai / Valtio / Redux Toolkit / Preact Signals for solo work. [Docs](https://github.com/pmndrs/zustand)

- **TanStack Query v5** — alternative to a hand-rolled pub/sub for SQLite reactivity (manual `invalidateQueries` after every mutation). Heavier-weight pattern; the hand-rolled table-keyed pub/sub (~80 LOC, ports straight to Swift) is the lighter and more portable option. [Docs](https://tanstack.com/query/latest)

- **chokidar** — file watcher. [GitHub](https://github.com/paulmillr/chokidar) (audit recommended evaluating `@parcel/watcher` as a faster alternative — pending review)

- **@parcel/watcher v2.5+** — native FSEvents on macOS; used by VSCode/Nx/Tailwind; ms vs seconds on large trees compared to chokidar. Gotchas: editor atomic-save (write `.tmp` + rename) emits create+delete for the temp; debounce 50–100ms by path. APFS clones don't fire events. [npm](https://www.npmjs.com/package/@parcel/watcher)

- **gray-matter** — YAML frontmatter parser. [GitHub](https://github.com/jonschlinkert/gray-matter) (upstream stale since 2019; audit recommended `@11ty/gray-matter` fork or `remark-frontmatter` — pending review)

#### Markdown / parsing

- **remark + remark-directive + mdast-util-directive** — Markdown parser + container directive support for `:::columns`, `:::callout`. `directiveToMarkdown()` round-trips back to `:::` syntax. Nesting requires the outer fence to use more colons (`::::columns` containing `:::callout`) to avoid ambiguous closes. [remark](https://github.com/remarkjs/remark) · [remark-directive](https://github.com/remarkjs/remark-directive) · [mdast-util-directive](https://github.com/syntax-tree/mdast-util-directive)

- **@flowershow/remark-wiki-link v3.3.1+** — Obsidian-flavored wikilink parser; handles `[[name]]`, `[[name|alias]]`, `[[name#heading]]`, combined `[[name#heading|alias]]`, and `![[asset]]` embeds. Healthiest of the maintained options (alternatives `@portaljs/remark-wiki-link` ~2yr stale; `heavycircle/remark-obsidian` solo-maintained). [GitHub](https://github.com/flowershow/remark-wiki-link)

#### Drag-and-drop (Spaces)

- **dnd-kit** — drag-and-drop for the Spaces composer. Two confusingly-named packages: [@dnd-kit/core](https://github.com/clauderic/dnd-kit) (v6.x, stable) and [@dnd-kit/react](https://dndkit.com/react/) (v0.x, ground-up rewrite, pre-1.0).
