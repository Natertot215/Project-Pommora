### Pommora — Roadmap Reorder: Tier Model

> RC-session brainstorm output. Authored end-of-2026-05-18 post-v0.2.7.0 / pre-v0.2.7.1. Supersedes the per-minor ordering in `Framework.md` from v0.2.7.2 onward.

#### Why this exists

`Framework.md` currently mixes "new feature" and "polish" inside the v0.2.7.x patch family (NavDropdown at .2, Tables-custom-grid at .3) and defers paradigm-completing work (Properties, wikilinks) behind multiple polish patches. The actual reasoning behind the ordering had drifted from the project's foundational pattern: build a scaffold, then polish it, then build the next scaffold on top.

Nathan's stated thesis at RC session: **"Polish what we have, then move on to the larger functional structures that support the interaction. Spaces views come AFTER everything Spaces are meant to be used with."**

That's a **tier model**, not a sequence. It re-applies the same scaffolding pattern that produced v0.1.0 (data scaffold) and v0.2.0 (paradigm scaffold) — now as a third scaffold pass spanning post-v0.2.7.0 through v1.0.0.

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

The polish-vs-new filter applied at the patch level:
- **Polish** = refines a surface that already exists and is functionally complete.
- **New** = adds a capability that doesn't currently exist.

Six items previously scheduled inside v0.2.7.x or v0.2.9/.10 fail the polish filter and re-home to their proper minor versions: NavDropdown, Tables-custom-grid, wikilinks-with-autocomplete, directives, slash menu, heading fold.

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

##### What v0.2.7.x removes from the previous list

- **Tables custom grid** — substantial TextKit-2 work (NSTextLayoutFragment subclass with per-cell hit-testing). Source-aligned rendering shipped at v0.2.7.0 is functional. Re-home to v0.6.0 Vault-views or v1.0.0 polish.
- **NavDropdown** — new navigation surface, not polish. Re-homes to v0.7.0 productivity-surface version.

---

#### Tier B — Operational foundation (5 minors)

Each minor closes a layer of the operational paradigm. After all five, everything Spaces are meant to consume is shipped.

##### v0.3.0 — Properties

**Closes the Items paradigm.** Items have been data-only since v0.2.0 — Vault `_vault.json.properties[]` is empty in v0.2.0; this is where the schema actually fills up. Pages also gain full property editing.

- **Vault property-schema editor** — `+ Add property` button → name + type picker → per-type config (options for Select, scope for Relation, etc.). Edits `_vault.json.properties[]` atomically.
- **Per-type property editors** — fully wire the existing `PropertyEditorRow` dispatch (TextField / Toggle / DatePicker / Picker / `MultiSelectChips`) into both Pages inspector and Item Window.
- **tier1 / tier2 / tier3 chip relation editors** — type-to-search relation pickers backed by Space / Topic / Sub-topic managers.
- **Vault schema mutations** — rename / type-change (lossless only) / delete; cross-member rewrite using the same atomic-transaction pattern as future wikilink rename cascade.
- **Item Window redesign** per Nathan's WIP sketch — modal `WindowGroup(for: ItemRef.self)`, 2-col body (description left, properties right), Delete/Save footer.
- **Item creation surfacing** — Vault detail footer `+ New Item`, Collection row right-click → `New Item (in This Collection)`, Vault row right-click → `New Item`. Sidebar.md right-click table updated.

End of v0.3.0: data model is feature-complete. Pages and Items both have body content AND properties AND tier1/2/3 relations editable in-app.

##### v0.4.0 — Pages editor expanded

**Pages editor reaches feature-complete per `// Features//Pages.md`.** Capitalizes on engine being fresh in context.

- **`:::callout` directive** — parser via Apple AST `BlockDirective` walker (engine groundwork already wired). Renders as outlined box, distinct from blockquote.
- **`@Columns` directive** — multi-column section rendering. Renders as CSS-grid-equivalent layout (TextKit-2 multi-column via NSTextContainer geometry).
- **Heading fold** — chevrons on heading rows; collapse/expand the section under each heading. Persist per-document fold state in editor model.
- **Slash menu** — `/` trigger → popover menu for inserting blocks (tables / HR / code blocks / blockquotes / callout / columns / headings).

End of v0.4.0: Pages editor matches Pages.md spec end-to-end.

##### v0.5.0 — SQLite + live-data infrastructure

**The "live data" version.** Disk and app stay in sync; cross-entity navigation indexed; deletes recoverable via UI.

- **SQLite indexer (GRDB.swift v7.5+)** — rebuilt from files on launch; six-table schema from PRD (`pages` / `items` / `agenda` / `vaults` / `tiers` / `links`). Per-nexus DB at `~/Library/Application Support/Pommora/nexuses/<nexus-id>/nexus.db` (outside the nexus to avoid iCloud-sync locking).
- **File watcher (FSEventStream)** — external changes update SQLite + sidebar live; atomic-write detection (debounce + outbound mtime tracking to ignore Pommora's own writes).
- **Wikilinks indexed from day one**:
  - `[[Title]]` autocomplete popover (queries SQLite live)
  - Click routing (Page → opens in detail pane; Context → detail pane; Item → ItemWindow popover)
  - Rename cascade rewrite via SQLite-indexed lookup (NOT naive body scan — no two-step)
- **Trash UI window** — `.trash//` data already shipped v0.2.5; v0.5.0 adds the SwiftUI surface listing entries with restore + permanent-delete + Empty Trash.
- **Cross-Vault move-strip** — Notion-style; confirm dialog lists props that will be stripped.
- **External-edit detection on Page save** — when editor saves a Page whose mtime drifted since editor mount, prompt before overwriting.

End of v0.5.0: filesystem and app are live-synced. Wikilinks work like Obsidian.

##### v0.6.0 — Vault view types

**Vaults stop being lists of files; become real database views.**

- **Five view types**: table / board (kanban grouped by property options) / list / cards / gallery.
- **Inline cell editing** in Table view.
- **Per-view controls**: filter / sort / group / shown-properties (powered by v0.5.0 SQLite + `json_extract`).
- **Saved view configurations** stored in `_vault.json`. `views` field becomes populated and editable.
- Board view ships as visual kanban; cards group by a property's options; editing a card moves it visually. Drag-to-rewrite-frontmatter on kanban is a post-v1 follow-up.

End of v0.6.0: Pommora's Notion-like value proposition is visible to the user.

##### v0.7.0 — Productivity surface complete

**System integration + onboarding + nav history + Settings.** The "polish and integration" pass — all the pieces that make Pommora feel like an app rather than a prototype.

- **EventKit bridge** — Sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys + modern `requestFullAccessTo*` APIs. Bidirectional mirroring (`EKEvent` for items with `start_at` + `end_at`; `EKReminder` for items with `due_at` or unscheduled). **Opt-in via Settings.**
- **Agenda UI** — Item Window parallel to existing Item Window (time-field collapse per Agenda.md); Calendar view replacing the placeholder Saved → Calendar entry; menu-bar Quick Capture.
- **Settings scene** (`⌘,`) — Tier-config editor (singular + plural labels; `tagging_style`; `exposed` toggle); Saved-section labels editor; EventKit sync opt-in toggle; accent color + font size customization.
- **NavDropdown** — Liquid Glass dropdown button in toolbar (SF Symbol `square.on.square`) opening popover with `[Favorites | Recents]` segmented Picker + scrollable list. `EntityRef` generalization wires `WindowGroup(for: EntityRef.self)` for standalone preview windows. Recents 500-store/100-display LRU; Favorites uncapped with hover-star toggle. Back/Forward arrows + `⌘[`/`⌘]`. `⌘T` opens. Persistence at `<nexus>/.nexus/state.json`.
- **Accessibility checkpoint** — VoiceOver labels + focus order + Dynamic Type respect across all v0.2.0-v0.6.0 surfaces.
- **Performance budgets verified** — Page open time, sidebar N-row render, Vault view 1000-row scroll.
- **First-launch UX** — empty-state copy; nexus-picker polish; discoverable menu-bar Quick Capture entry.
- **Saved section content fills in** — Recents (full-frame view backed by NavDropdown's RecentsManager); Calendar (with EventKit mirror visible if opt-in).

End of v0.7.0: Pommora is integration-complete, accessible, performant, and onboards new users without surprises.

---

#### Tier C — Interaction layer (2 minors + stabilization)

##### v0.8.0 — Composed-blocks editor for Contexts + Homepage

**The capstone.** Spaces / Topics / Sub-topics / Homepage finally get their composed-blocks surface — the dashboard concept that's been a placeholder since v0.2.0.

- **Block types**: paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (live, fully editable per the inline-editing principle — works because Vault views shipped at v0.6.0), linked-pages widget, link-list widget.
- **Drag-and-drop reordering**; slash-menu insertion.
- `ContextDetailPlaceholder` retires.

End of v0.8.0: organization layer becomes substantive. The 2-layer model claim is honored end-to-end.

##### v0.9.0 — Global search + rich blocks

- **Global FTS5 search** over Page bodies, Item descriptions, Agenda titles, frontmatter / properties (extends v0.5.0 SQLite). `⌘K` command palette.
- **Mini-calendar widget** showing Agenda items inline in Contexts/Homepage.
- **Additional block types** as needed once the basics are exercised.

##### v1.0.0 — Stabilization

No new features. Polish + perf + bug-fix across everything v0.0.0 → v0.9.0. Final accent / typography pass. Release-readiness checklist (Sparkle if non-MAS, TestFlight if MAS).

---

#### Comparison to previous Framework

##### Net changes from the previous Framework

| Item | Previous slot | New slot | Why |
|---|---|---|---|
| Tables custom grid | v0.2.7.3 (patch) | v0.6.0 or later (Vault-views or v1.0.0 polish) | Substantial new feature, not polish. Source-aligned rendering at v0.2.7.0 is functional. |
| NavDropdown | v0.2.7.2 / v0.2.8 (patch / minor) | v0.7.0 (productivity-surface) | New navigation surface, not polish. Coexists naturally with Settings + Quick Capture. |
| Directives (`:::callout`, `@Columns`) | v0.2.9 (patch-numbered minor) | v0.4.0 (Pages-editor-expanded minor) | New capabilities; minor-version-worthy. |
| Heading fold | v0.2.9 | v0.4.0 | Same. |
| Slash menu | v0.2.9 | v0.4.0 | Same. |
| Wikilinks (autocomplete + click + rename cascade) | v0.2.10 | v0.5.0 (with SQLite) | Indexed from day one — no naive→indexed rewrite. |
| Properties | v0.3.0 (existing) | v0.3.0 (kept) | Confirmed first foundation minor — closes the longest-running paradigm hole. |
| SQLite + Watcher | v0.4.0 (existing) | v0.5.0 | Shifts one minor later to accommodate Pages-editor-expanded at v0.4.0. |
| Trash UI | v0.4.0 (existing) | v0.5.0 | Bundled with SQLite + Watcher cluster. |
| Vault views | v0.5.0 (existing) | v0.6.0 | Same content; shifted one minor later. |
| EventKit + Agenda + Settings + a11y + perf + onboarding | v0.6.0 (existing) | v0.7.0 | Same bundle; shifted one minor + NavDropdown absorbed. |
| Composed-blocks Contexts | v0.7.0 (existing) | v0.8.0 | Same content; shifted one minor later. |
| Global search + rich blocks | v0.8.0 (existing) | v0.9.0 | Same content; shifted one minor later. |
| Stabilization | v1.0.0 | v1.0.0 | Unchanged. |

##### Count check

- **Previous:** v0.2.7 + v0.2.8 + v0.2.9 + v0.2.10 + v0.3.0–v0.8.0 + v1.0.0 = 4 patch-numbered-as-minors + 6 minors + 1 major = 11 versions.
- **New:** v0.2.7.1–.3 + v0.3.0–v0.9.0 + v1.0.0 = 3 patches + 7 minors + 1 major = 11 versions.

Same total. The naming now matches actual scope of each version.

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

- **Tables-custom-grid final home** — v0.6.0 (Vault-views, since cell-edit is a related interaction model) vs. v1.0.0 (stabilization polish). Defer to v0.6.0 prep.
- **Search FTS5 schema timing** — could ship the FTS5 tables alongside SQLite at v0.5.0 (cheap; index is already there) and only the `⌘K` UI defers to v0.9.0. Or wait. Defer to v0.5.0 prep.
- **Where do Sub-topic-specific composed blocks differ from Topic / Space?** — open from before; settles inside v0.8.0 prep.
- **NavDropdown vs. ⌥⌘O standalone window opening** — both ship at v0.7.0; verify the interactions don't conflict.

#### What this document is NOT

- Not an implementation plan. Implementation plans are per-version, created at the start of each version's session.
- Not a binding contract. Future sessions can re-question this ordering if a new constraint surfaces (a v0.3.0 Properties session might reveal that Pages-editor-expansion needs to come first for some technical reason).
- Not a date plan. Per Studio rules, no calendar dates — phases and steps only.

---

#### Next steps (per Studio convention)

1. Deploy this doc to `//The Studio//Projects//Project Pommora//.claude/Planning/Roadmap-Reorder-Tier-Model.md` when back at desk (Nexus-first per RC session rule; Studio after).
2. Update `Framework.md` "Phases" section + "Roadmap reorders (cumulative history)" to reflect the tier model (add 2026-05-19 entry).
3. Update `Handoff.md` "Next session priorities" — replace the v0.2.7.x list with the new 3-patch bundle.
4. Update `CLAUDE.md` "Active Version" block — replace the v0.2.7.x list with the new 3-patch bundle; remove "v0.2.9" + "v0.2.10" references.
5. Reconcile `// Features//NavDropdown.md` and `PommoraPRD.md` version references — both currently say v0.2.8; new slot is v0.7.0.
6. NO immediate implementation plan needed — v0.2.7.1 already has its verbatim resume prompt in `Handoff.md`.
