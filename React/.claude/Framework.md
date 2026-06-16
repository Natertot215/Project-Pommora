## Framework — React Rebuild Roadmap

The full program roadmap (with rationale, the two research workflows behind it, and the deferred frontier) lives at `// Projects // Project Pommora // .claude // Planning // 06-14-React-Rebuild-Roadmap.md`. This is the lean status view.

### Scope (locked)

The initial rebuild is the proven back half + the two shipped renderers + editor + navigation — **the "core 7"**, nothing from the spec-only frontier:

1. Data layer (incl. Agenda Task/Event entities — schema only, no surfacing)
2. Properties
3. Connections
4. Markdown editor (**CodeMirror 6**)
5. Navigation (shell + sidebar + nav dropdown)
6. Table view
7. Gallery view

**Deferred frontier** (post-core): block editor (Contexts-as-blocks + Homepage), Agenda surfacing + calendar sync, Board/List/Cards renderers, Settings editing UI, global search, LLM-chat inspector, type-to-find, OS integrations (Electron `Tray` covers basic menu-bar; a thin native Swift helper only if deeper hooks are wanted).

### Phase status

- **Phase 1 — Window + glass sidebar (read-only skeleton):** ✅ shipped. Window + glass sidebar reading `~/test` via `readNexus` → IPC → store → recursive sidebar. No function. (See `Planning/Phase-1-Window-Sidebar-Scaffold.md`.)
- **Phase 2 — Navigation function + views (read-only):** 🔬 in progress (build workflow). Selection → detail; page open + render (read-only); pure view pipeline; Table + Gallery; view switcher.
- **Phase 3 — Write path:** ⬜ next. Atomic write + order-preserving frontmatter merge; create/rename/move; the careful, tested write half.
- **Phase 4 — Properties & Connections:** ⬜ discriminated property types + cell editors; `[[ ]]` links + rename cascade.
- **Phase 5 — Page editor (CodeMirror 6):** ⬜ controlled component, frontmatter↔body, debounced save, wikilink/embed decorations.
- **Phase 6 — Contexts, settings, the frontier:** ⬜ deferred.

### Gates carried forward

- **Glass:** Apple-Regular CSS in place; `liquid-dom` shelved (experimental). Revisit when HTML-in-Canvas ships unflagged.
- **Table is the historical risk** (failed twice in SwiftUI) — render it early and confirm before building outward. (Phase 2 brings it up now.)
- **Two design forks already settled:** single-window-now-multi-window-ready; modernized TS-native on-disk format.
