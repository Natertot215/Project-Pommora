### React State + Data Layer

Zustand v5+ vanilla (`useSyncExternalStore`), hand-rolled table-keyed pub/sub for `better-sqlite3` reactivity (~80 LOC), `@parcel/watcher` v2.5+ with APFS / atomic-save gotchas, FTS5 `unicode61` (`remove_diacritics=2`) external-content mode for nexus-scale search.

> **Status:** Reference. Swift uses `@Observable` + GRDB `ValueObservation.tracking { ... }.values(in:)` for the same role.

---

#### State, data, file watching

**State.** Zustand v5+ vanilla. `zustand/vanilla`'s `createStore` produces a framework-agnostic store that React binds to via `useSyncExternalStore`. The framework-agnostic shape keeps the state pattern translatable to a future Swift rebuild (the conceptual equivalent on Swift is `@Observable` + GRDB `ValueObservation`). Avoid: Jotai (atom-first; viral across the codebase), Valtio (Proxy magic fights TypeScript), Redux Toolkit (overkill for solo work), Preact / TC39 Signals (not stable for production).

**Reactive SQLite layer.** `better-sqlite3` is synchronous and emits no change events, so reactivity is fully manual. Recommended pattern: hand-rolled table-keyed pub/sub — mutations publish touched tables; the Adapter holds a `Map<table, Set<queryFn>>` and re-runs subscribers. ~80 LOC, perfectly portable to Swift if a future migration ever happens. TanStack Query v5 with explicit `invalidateQueries` is the heavier-weight alternative if hand-rolled discipline isn't preferred.

**File watching.** `@parcel/watcher` v2.5+ in the Electron main process; IPC events across to the renderer. Gotchas:

- Editor atomic-save (write to `.tmp` + rename) emits `create` then `delete` for the temp; debounce 50–100ms by path
- APFS clones don't fire events
- Track outbound mtimes to ignore Pommora's own writes

**Search.** SQLite FTS5 with `unicode61` tokenizer (`remove_diacritics=2`) + external-content mode pointing at the `pages` table. Trigram tokenizer is 2× insert cost — only enable if substring search becomes a requirement. MiniSearch (in-memory) is fine up to ~2k notes but balloons memory at 10k. For Pommora's 1k–10k nexus scale, FTS5 wins decisively.

---

#### Verified library findings

- **`@parcel/watcher` v2.5+** for nexus folder watching — native FSEvents on macOS; ms vs seconds vs chokidar at large tree scale. Used by VSCode, Nx, Tailwind.
- **`better-sqlite3` (WAL mode) + SQLite FTS5** for the local index. External-content table + `unicode61` tokenizer (`remove_diacritics=2`) is the recommended pattern for nexus scale (1k–10k pages).
