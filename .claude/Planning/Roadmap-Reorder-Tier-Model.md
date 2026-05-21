### Pommora — Roadmap Reorder: Tier Model

> RC-session brainstorm. Authored end-of-2026-05-18 post-v0.2.7.0 / pre-v0.2.7.1. Supersedes per-minor ordering in `Framework.md` from v0.2.7.2 onward.

#### Why this exists

`Framework.md` had mixed new-feature and polish inside the v0.2.7.x patch family and deferred paradigm-completing work (Properties, wikilinks) behind multiple polish patches.

Nathan's RC thesis: **"Polish what we have, then move on to the larger functional structures that support the interaction. Spaces views come AFTER everything Spaces are meant to be used with."**

A **tier model**, not a sequence — re-applies the scaffolding pattern that produced v0.1.0 (data scaffold) and v0.2.0 (paradigm scaffold) as a third pass through v1.0.0.

#### The tier model

```
Tier A — Polish (v0.2.7.x patches)
   Refine surfaces that already exist and are functionally complete.
   No new capabilities.

Tier B — Operational foundation (v0.3.0 → v0.7.0)
   Build the data + index + view + integration layer.
   Everything Spaces are meant to USE.

Tier C — Interaction layer (v0.8.0 → v0.9.0 + stabilization)
   Build the Contexts/Spaces composed-blocks surface that CONSUMES the foundation.
   Final feature work before v1.0.0.
```

Polish-vs-new filter at the patch level:
- **Polish** — refines a complete existing surface.
- **New** — adds a capability that doesn't exist.

Six previously-scheduled items fail the polish filter and re-home: NavDropdown, Tables-custom-grid, wikilinks-with-autocomplete, directives, slash menu, heading fold.

#### Tier A — Polish (v0.2.7.x)

Three patches. Each refines a surface shipped at v0.2.7.0 or earlier.

##### v0.2.7.1 — Editor polish

- **Blockquote** Apple-Notes parity. Add `drawBlockquote(at:in:)` to `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift` analogous to `drawCodeBlockBackground`: vertical accent bar on leading edge + heavier background shading. Mark ranges via new `.pommoraBlockquote: true` attribute from `AppleASTSupplementalStyler.visitBlockQuote`.
- **HR (`---`)** three fixes:
  - Auto-transform lock: typing `---` on its own line locks as HR; further `-` rejected.
  - Inset visual width by `textInsets.horizontal` so the line stops at body-text width, not container.
  - Color confirm at `NSColor.separatorColor` 80% alpha (already macOS-recommended).
- Verbatim resume prompt at top of `Handoff.md`.

##### v0.2.7.2 — Sidebar reorder + drag

- Drag Pages between Vault Collections.
- Reorder Spaces / Topics / Sub-topics within their parents.
- Reorder Vaults at the root.
- SwiftUI `.draggable(_:)` + `.dropDestination(for:)` with custom `Transferable` types per entity kind.
- Persist via new `_order: [<id>]` field on parent JSON sidecar (Vault's `_vault.json`, Collection's `_collection.json`, tier-1 Spaces config). Filesystem reads stay authoritative; order is an overlay.

##### v0.2.7.3 — Closing deferred Pages-editor work

- **Phase 4.5 polish** from v0.2.7-engine-swap plan: selection-wrap (typing `*` with selection → `*text*`), auto-exit-on-whitespace, 11-test auto-pair suite.
- **Phase 3 AST tokenizer rewrite**: wholesale-rewrite engine's `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`. Delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. Internal cleanup; not user-visible. Unifies everything onto Apple AST.
- **Developer cosmetics**: catch-rewrap (`do { try await … } catch { … }` ~12 single-line patterns in SidebarView + IconPickerSheet), CI `working-directory: .` removal, outdated `Page-Editor-Plan.md` Tiptap-locked language sync-or-delete.

##### What v0.2.7.x removes

- **Tables custom grid** — substantial TextKit-2 work; source-aligned rendering at v0.2.7.0 is functional. Re-home to v0.6.0 or v1.0.0.
- **NavDropdown** — new navigation surface, not polish. Re-homes to v0.7.0.

---

#### Tier B — Operational foundation (5 minors)

Each minor closes a layer. After all five, everything Spaces consume is shipped.

##### v0.3.0 — Properties

**Closes the Items paradigm.** Items have been data-only since v0.2.0; this fills the schema. Pages gain full property editing.

- **Vault property-schema editor** — `+ Add property` → name + type picker → per-type config. Edits `_vault.json.properties[]` atomically.
- **Per-type property editors** — wire `PropertyEditorRow` dispatch (TextField / Toggle / DatePicker / Picker / `MultiSelectChips`) into Pages inspector + Item Window.
- **tier1 / tier2 / tier3 chip relation editors** — type-to-search pickers backed by Space / Topic / Sub-topic managers.
- **Vault schema mutations** — rename / type-change (lossless) / delete; cross-member rewrite via atomic-transaction.
- **Item Window redesign** — modal `WindowGroup(for: ItemRef.self)`, 2-col body, Delete/Save footer.
- **Item creation surfacing** — Vault detail footer `+ New Item`, Collection/Vault row right-click `New Item`. Sidebar.md table updated.

End of v0.3.0: data model feature-complete. Pages and Items have body, properties, and tier1/2/3 relations editable in-app.

##### v0.4.0 — Pages editor expanded

**Editor reaches feature-complete per `// Features//Pages.md`.** Capitalizes on engine being fresh in context.

- **`:::callout` directive** — parser via Apple AST `BlockDirective` walker (engine groundwork already wired). Renders as outlined box, distinct from blockquote.
- **`@Columns` directive** — multi-column section rendering. Renders as CSS-grid-equivalent layout (TextKit-2 multi-column via NSTextContainer geometry).
- **Heading fold** — chevrons on heading rows; collapse/expand the section under each heading. Persist per-document fold state in editor model.
- **Slash menu** — `/` trigger → popover menu for inserting blocks (tables / HR / code blocks / blockquotes / callout / columns / headings).

End of v0.4.0: editor matches Pages.md spec end-to-end.

##### v0.5.0 — SQLite + live-data infrastructure

**The "live data" version.** Disk + app stay in sync; cross-entity nav indexed; deletes recoverable.

- **SQLite indexer (GRDB.swift v7.5+)** — rebuilt from files on launch; six-table schema (`pages`/`items`/`agenda`/`vaults`/`tiers`/`links`). Per-nexus DB at `~/Library/Application Support/Pommora/nexuses/<nexus-id>/nexus.db` (outside nexus to avoid iCloud-sync locking).
- **File watcher (FSEventStream)** — external changes update SQLite + sidebar live; atomic-write detection (debounce + outbound mtime tracking).
- **Wikilinks indexed from day one** — `[[Title]]` autocomplete (live SQLite), click routing, rename cascade via indexed lookup (no naive body scan).
- **Trash UI window** — `.trash//` data shipped v0.2.5; v0.5.0 adds the SwiftUI surface (restore + permanent-delete + Empty Trash).
- **Cross-Vault move-strip** — Notion-style; confirm dialog lists stripped props.
- **External-edit detection on Page save** — prompt before overwriting if mtime drifted since editor mount.

End of v0.5.0: filesystem + app live-synced. Wikilinks work like Obsidian.

##### v0.6.0 — Vault view types

**Vaults stop being lists; become real database views.**

- **Five view types**: table / board (kanban) / list / cards / gallery.
- **Inline cell editing** in Table view.
- **Per-view controls**: filter / sort / group / shown-properties (powered by v0.5.0 SQLite + `json_extract`).
- **Saved view configurations** in `_vault.json`. `views` field populates.
- Board view ships visual; drag-to-rewrite-frontmatter is post-v1.

End of v0.6.0: Pommora's Notion-like value proposition visible.

##### v0.7.0 — Productivity surface complete

**System integration + onboarding + nav history + Settings.** The polish-and-integration pass.

- **EventKit bridge** — Sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys + modern `requestFullAccessTo*` APIs. Bidirectional mirroring (`EKEvent` for `start_at`+`end_at`; `EKReminder` for `due_at` or unscheduled). **Opt-in via Settings.**
- **Agenda UI** — Item Window (time-field collapse per Agenda.md); Calendar view replacing the Saved → Calendar placeholder; menu-bar Quick Capture.
- **Settings scene** (`⌘,`) — Tier-config editor; Saved-section labels; EventKit opt-in toggle; accent + font size.
- **NavDropdown** — Liquid Glass dropdown (SF Symbol `square.on.square`) opening popover with `[Favorites | Recents]` segmented Picker. `EntityRef` wires `WindowGroup(for: EntityRef.self)` for preview windows. Recents 500-store/100-display LRU; Favorites uncapped. Back/Forward + `⌘[`/`⌘]`. `⌘T` opens. Persistence at `<nexus>/.nexus/state.json`.
- **Accessibility checkpoint** — VoiceOver + focus order + Dynamic Type across v0.2.0–v0.6.0 surfaces.
- **Performance budgets** — Page open, sidebar N-row render, Vault 1000-row scroll.
- **First-launch UX** — empty-state copy, nexus-picker polish, menu-bar Quick Capture entry.
- **Saved section content** — Recents (RecentsManager-backed); Calendar (EventKit mirror if opt-in).

End of v0.7.0: Pommora is integration-complete, accessible, performant, onboards cleanly.

---

#### Tier C — Interaction layer (2 minors + stabilization)

##### v0.8.0 — Composed-blocks editor for Contexts + Homepage

**The capstone.** Contexts and Homepage get their composed-blocks surface — the dashboard concept placeholder since v0.2.0.

- **Block types**: paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (live, editable; works because Vault views shipped at v0.6.0), linked-pages, link-list.
- **Drag-and-drop reordering**; slash-menu insertion.
- `ContextDetailPlaceholder` retires.

End of v0.8.0: organization layer becomes substantive; 2-layer model honored end-to-end.

##### v0.9.0 — Global search + rich blocks

- **Global FTS5 search** over Page bodies, Item descriptions, Agenda titles, frontmatter / properties (extends v0.5.0 SQLite). `⌘K` command palette.
- **Mini-calendar widget** showing Agenda items inline in Contexts/Homepage.
- **Additional block types** as needed once the basics are exercised.

##### v1.0.0 — Stabilization

No new features. Polish + perf + bug-fix across v0.0.0 → v0.9.0. Final accent / typography pass. Release-readiness checklist (Sparkle non-MAS, TestFlight MAS).

---

#### Comparison to previous Framework

##### Net changes from the previous Framework

| Item | Previous | New | Why |
|---|---|---|---|
| Tables custom grid | v0.2.7.3 | v0.6.0 / v1.0.0 | Substantial new feature, not polish. |
| NavDropdown | v0.2.7.2 / v0.2.8 | v0.7.0 | New nav surface; coexists with Settings + Quick Capture. |
| Directives (`:::callout`, `@Columns`) | v0.2.9 | v0.4.0 | New capabilities; minor-version-worthy. |
| Heading fold | v0.2.9 | v0.4.0 | Same. |
| Slash menu | v0.2.9 | v0.4.0 | Same. |
| Wikilinks (autocomplete + click + rename) | v0.2.10 | v0.5.0 | Indexed from day one — no naive→indexed rewrite. |
| Properties | v0.3.0 | v0.3.0 | First foundation minor — closes the longest-running paradigm hole. |
| SQLite + Watcher | v0.4.0 | v0.5.0 | Shifts to accommodate Pages-editor-expanded at v0.4.0. |
| Trash UI | v0.4.0 | v0.5.0 | Bundled with SQLite + Watcher. |
| Vault views | v0.5.0 | v0.6.0 | Shifted one minor later. |
| EventKit + Agenda + Settings + a11y + perf + onboarding | v0.6.0 | v0.7.0 | Shifted one minor + NavDropdown absorbed. |
| Composed-blocks Contexts | v0.7.0 | v0.8.0 | Shifted one minor later. |
| Global search + rich blocks | v0.8.0 | v0.9.0 | Shifted one minor later. |
| Stabilization | v1.0.0 | v1.0.0 | Unchanged. |

##### Count check

- **Previous:** v0.2.7 + v0.2.8 + v0.2.9 + v0.2.10 + v0.3.0–v0.8.0 + v1.0.0 = 4 + 6 + 1 = 11 versions.
- **New:** v0.2.7.1–.3 + v0.3.0–v0.9.0 + v1.0.0 = 3 + 7 + 1 = 11 versions.

Same total. Naming now matches actual scope.

---

#### Decisions locked at this brainstorm

1. **Polish-vs-new filter applied at the patch level.** Patches only refine working surfaces; new capabilities ship as minor versions.
2. **Tier model adopted as the framing.** Polish → Foundation → Interaction.
3. **v0.2.7.x bundle: 3 patches** (blockquote+HR, sidebar drag, Phase-4.5+AST+cosmetics).
4. **Properties at v0.3.0.** First foundation minor closes the longest-running paradigm hole.
5. **Wikilinks coupled with SQLite at v0.5.0.** Indexed from day one — no two-step rewrite.
6. **NavDropdown at v0.7.0.** Natural home alongside Settings + Quick Capture + a11y pass.
7. **Tables-custom-grid out of patch family.** Re-homes to v0.6.0 or v1.0.0 polish.
8. **Spaces composed-blocks at v0.8.0.** Capstone — after everything Spaces consume is shipped.

#### Decisions still open

- **Tables-custom-grid final home** — v0.6.0 vs. v1.0.0. Defer to v0.6.0 prep.
- **Search FTS5 schema timing** — could ship FTS5 tables alongside SQLite at v0.5.0; `⌘K` UI defers to v0.9.0. Defer to v0.5.0 prep.
- **Sub-topic-specific composed blocks vs. Topic / Space** — settles inside v0.8.0 prep.
- **NavDropdown vs. ⌥⌘O standalone window opening** — both at v0.7.0; verify interactions don't conflict.

#### What this document is NOT

- Not an implementation plan (plans are per-version, at the start of each version's session).
- Not a binding contract — future sessions can re-question if a new constraint surfaces.
- Not a date plan (Studio rule: phases and steps only).

---

#### Next steps

1. Deploy to `//The Studio//Projects//Project Pommora//.claude/Planning/Roadmap-Reorder-Tier-Model.md` (Nexus-first per RC rule).
2. Update `Framework.md` "Phases" + "Roadmap reorders (cumulative history)" — add 2026-05-19 entry.
3. Update `Handoff.md` "Next session priorities" — replace v0.2.7.x list with the new 3-patch bundle.
4. Update `CLAUDE.md` "Active Version" — replace v0.2.7.x list; remove v0.2.9 + v0.2.10 references.
5. Reconcile `// Features//NavDropdown.md` and `PommoraPRD.md` version references (currently v0.2.8; new slot is v0.7.0).
6. No implementation plan needed — v0.2.7.1 has its resume prompt in `Handoff.md`.
