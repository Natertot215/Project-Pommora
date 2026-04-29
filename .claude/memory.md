# Project Memory — Pommora

Running log of non-obvious project state, decisions, and constraints that are not derivable from the code or git history. Newest entries at the top.

---

## 2026-04-28 — Session: bug fixes + column independence

**Stable base:** Walking skeleton at commit `d73b6ba` ("Add lessons directory + screenshots scratch folder"). This is the confirmed working foundation. The session prior (`c6d3678c`) attempted 4 drag-reorder rewrites and multiple sidebar compression passes, all reverted at Nathan's request.

**What was fixed in this session:**
- `LibrarySearch.run` now includes orphan files (previously silently excluded)
- `EditorView.lastOpenedAt` only stamped on successful file read (was stamping even on failure)
- `SidebarView.filesContent` orphan overflow branch deleted (scrapped-feature artifact — `orphanRow`, `cappedOrphanHeight`, `orphanVisibleCap` all gone)
- `FileIO.write` force-unwraps `data(using: .utf8)!` instead of silently optional-chaining
- `NavigationSplitView` uses `.prominentDetail` so sidebar/content columns resize independently

**Drag-reorder is deferred:** Finder-style displacement drag (source dims in place, gap at drop point, no blue bar) is architecturally blocked in `.listStyle(.sidebar)` — NSOutlineView takes over and renders the legacy blue insertion bar. The macOS 26 container-drag API only works correctly under `.listStyle(.inset)`. This is a v1.1 problem. The current app uses the original string-prefix drag (`"folder:UUID"`, `"file:UUID"`) with `withAnimation(.snappy)` live reorder on hover — the walking skeleton behavior.

**DerivedData:** One entry: `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Always pin with `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx` when running `xcodebuild`.

---

## Standing constraints (non-obvious, not in CLAUDE.md)

- **No AppKit wraps in v1.0.** Nathan explicitly: "swift ONLY items." `NSViewRepresentable` is off the table until v1.1.
- **Auto-save is OFF.** There is no save mechanism in MVP. `FileIO.write` exists but is not wired to any save trigger. This is intentional.
- **DebugSeed runs in DEBUG builds on app appear.** It seeds folders + files. When testing with large orphan counts, use `DebugSeed` rather than manually adding files.
- **`PBXFileSystemSynchronizedRootGroup`** — new `.swift` files in `Pommora/Pommora/` compile automatically. No `project.pbxproj` edit needed.
