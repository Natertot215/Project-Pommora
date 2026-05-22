### Paradigm Decisions

Pommora's value depends on its on-disk format, schemas, and cross-entity contracts surviving a stack rebuild and a future cloud sync (load-bearing constraints #1 and #2). Code locking those shapes is **paradigm-solidifying** — once data exists in the wild, migrating is expensive.

#### Operating rule

**Stop and surface paradigm choices for Nathan's confirmation before the code lands** — use `AskUserQuestion` with concrete trade-offs and your recommendation.

Applies even when a written plan proposes one path — if you spot ambiguity, a real downside, or an alternative worth weighing, surface it first. Spec drift is acceptable; silent commitment is not.

#### What counts as paradigm-solidifying

- **On-disk schema shapes** — fields, types, naming conventions, snake_case vs camelCase per-key choices, nesting structures inside `_schema.json` (Page Type / Item Type / Page Collection / Item Collection / AgendaTask / AgendaEvent) / `.space.json` / `.project.json` / `.task.json` / `.event.json` / etc.
- **Wire encodings for ambiguous types** — tagged-object vs bare-string discrimination (e.g. `.relation` vs `.select` strings), date format choices (ISO-8601 vs Unix epoch vs human-readable), null-vs-missing semantics.
- **Identifier conventions** — ULID format, filename-as-title rule, ID-vs-title display split, relation key shape (e.g. `{"$rel": "..."}`).
- **Default values that become locked once data exists** — seeded `_agenda.json` schema, `defaultSeed()` outputs for TierConfig / SavedConfig / Homepage, default property catalog per Vault.
- **File layout choices** — folder vs file boundaries for entities, filename extension conventions (`.project.json` vs `_project.json`), sidecar metadata file naming (`_schema.json` is the unified post-ParadigmV2 sidecar across all typed containers).
- **Cross-entity contracts** — tier1/tier2/tier3 array semantics, parent-pointer conventions (`parents: [String]` vs `parent: String?`), move-strip rules.
- **Error semantics at file load** — silent recovery (e.g. missing field → default) vs hard throw, malformed-file handling, validation timing.
- **Behavioral defaults that change user-visible outcomes downstream** — Topic-delete promote-vs-cascade default, filename collision handling (reject vs auto-suffix), move-across-Vault property-strip behavior.

#### What does NOT count

- **Internal implementation choices** that don't affect on-disk shape — use of `@Observable` vs `ObservableObject`, value types vs reference types, manager-per-entity vs unified store.
- **UI structure** — view extraction, sheet vs popover, sidebar layout — these can be refactored freely without data migration.
- **Test strategy** — Swift Testing vs XCTest, test file organization, fixture patterns.
- **Build configuration** — Swift version, strict concurrency settings (already locked).
- **Naming of types in code** — `Subtopic` vs `SubTopic`, internal CodingKeys names.

If in doubt, surface it. Better to overconfirm than retrofit.

#### Confirmation protocol

1. **Stop** before writing the locking line.
2. **State the choice in user-facing terms** — on-disk shape, user-visible behavior, migration cost. Not jargon.
3. **Present 2–3 options** with concrete on-disk samples. Lead with your recommendation.
4. **Wait for confirmation.** Update the spec/plan before dispatching implementation.
5. **Record the locked decision** in the registry below (or `History.md` if substantial).

#### Confirmed decisions

Each entry: date, decision, rationale.

- **2026-05-16 — `PropertyValue.relation` encodes as tagged object `{"$rel": "<ULID>"}`.** Bare-string `.relation` and `.select` are indistinguishable; tagged-object encoding makes relation edges legible to external agents and the graph-view indexer without consulting Vault schema (satisfies load-bearing constraint #3).
- **2026-05-16 — Collections persist a minimal `_collection.json` sidecar at `<nexus>/<Vault>/<Collection>/_collection.json`.** Shape: `{id: ULID, vault_id: ULID, modified_at: ISO-8601}`. Collection becomes Codable. Making the parent-Vault relation an explicit on-disk property keeps external query/parsing tools from having to infer it from filesystem nesting, and gives Collections stable portable IDs (replacing the SHA-256 path-hash fallback).
- **2026-05-16 — SF Symbol picker uses `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's own `IconPickerSheet` view.** Wrapping isolates call sites from the third-party API surface — swapping libraries (or moving to a hand-rolled grid) is a single-file rewrite in the wrapper, no call-site churn.

- **2026-05-17 — Stub-and-progressively-replace execution strategy for branch-spanning plans.** When tasks have forward-dependencies (row views reference later-task enums; sheets reference later manager methods), the spec's "defer commit until batch integration" produces N-task blobs where any break contaminates the whole batch. Instead: write each task with throwaway in-file stubs for not-yet-shipped types (e.g. `SheetStubView`, `SelectableRow` placeholders), later tasks replace stubs in-place. Every commit ships green standalone and is independently verifiable. Cleanup (stub removal) lives in a final task or rolls into the next dependent task. **Supersedes spec batch-commit instructions**.

- **2026-05-17 — Sidebar UX direction: right-click context menus replace all "+ New" affordances.** Locked in response to the always-visible "+ New" footer buttons being too noisy in the four-section sidebar. The replacement model:
  - **No "+ New" footer/inline buttons anywhere in the sidebar.** All 5 instances (SpacesSection, TopicsSection, VaultsSection, TopicRow "+ New Sub-topic", VaultRow "+ New Collection") removed.
  - **Right-click context menus are the canonical creation affordance, scoped by cursor location.** Right-click on a Vault row → "New Vault / New Collection / New Page" (all scoped to THAT Vault); right-click on a Collection row → "New Page" (scoped to THAT Collection); right-click on a Topic row → "New Sub-topic" (in THAT Topic); right-click in a Section area or on the heading → "New X" for that section. This is "the expected UIX" pattern from macOS Finder + Notion + Obsidian.
  - **"Saved" Section keeps its wrapper but loses the literal "Saved" header text** — Homepage / Calendar / Recents render heading-less at the top. The Section wrapper persists for the future pinned-page feature.
  - **Pages appear in the sidebar** under their parent Vault (root) or Collection via DisclosureGroup, with the `doc.text` icon. Click no-op until v0.3 editor.
  - **Items, Agenda items, Events do NOT appear in the sidebar.** They live exclusively in the detail-pane Tables (VaultDetailView / CollectionDetailView). Putting them in the sidebar would clutter without serving navigation; the detail pane is where Item discovery happens.
  - **Hover-icon "+" affordance on section headings explicitly skipped.** Right-click is the affordance. **Quick-capture** (Cmd+Shift+N / menu-bar capture) is the planned discoverable path, lands before v1.

- **2026-05-17 — Sidebar selection chrome via `.listRowBackground` at the row file level (not in-content `.background`).** Locked after a long polish iteration where the in-content workaround broke chevron coverage on DisclosureGroup-wrapped rows. Final shape:
  - **Chrome:** `Color.gray.opacity(0.10)` fill in a `RoundedRectangle(cornerRadius: 6, style: .continuous)` with `.padding(EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11))` — symmetric 11pt horizontal inset, 2pt vertical, matches search-bar width visually.
  - **Applied as `.listRowBackground(SelectionChrome(isSelected: SelectionTag.X(entity.id).matches(selection)))`** at each row file's body root. For DisclosureGroup-wrapped rows (TopicRow / VaultRow / CollectionRow), applied to the DisclosureGroup itself so chrome covers the chevron gutter; for flat rows + Saved items, applied to the row body.
  - **`SelectableRow` is generic** — `SelectableRow<Trailing: View>` with a `@ViewBuilder trailing:` slot defaulting to `EmptyView()`. Used by TopicRow for `ParentSpaceTags` (parent-Space color dots) so dots appear inside the chrome at the row's right edge.
  - **Row content geometry:** `HStack(spacing: 8)`; Image `.font(.system(size: 14, weight: .regular)).frame(width: 16, height: 16, alignment: .center)` (forces consistent glyph render size + centers in a fixed box so text always starts at the same X regardless of glyph natural width); padding `.padding(.leading, 4).padding(.trailing, 0).padding(.vertical, 6)`.
  - **Foreground:** selected icon + text shift to `Color.accentColor`; **text** gets `.brightness(0.10)`; **icon** gets no brightness modifier.
  - **`renamingRow` in all 6 row files** (Space / Topic / Subtopic / Vault / Collection / Page) mirrors SelectableRow's geometry exactly — entering rename doesn't visually jump.
  - **`SectionHeader` (private)** — `Section(isExpanded: $expanded) { rows } header: { SectionHeader(title:, onAdd:) }` for Spaces / Topics / Vaults; plain `Section { rows }` (no header arg) for Saved. SectionHeader's `+` button uses `.opacity(hovered ? 1 : 0).allowsHitTesting(hovered).animation(.easeInOut(duration: 0.12))` — opacity not conditional rendering to avoid layout shift; right-click anywhere on the header strip surfaces a "New" context menu regardless of hover state.

- **2026-05-17 → revised RC-2026-05-19 — Item creation surfacing lands at v0.3.0 paired with Properties; Item Window redesign at v0.3.1.** v0.2 ships only `CollectionDetailView` footer "+ New Item"; broader surfacing (Vault detail footer + Vault/Collection right-click + Sidebar.md table update) lands at v0.3.0 alongside the property panel. Item Window modal redesign (two-column body, Delete + Save footer) lands at v0.3.1. Rationale: an Item without Properties is just title + icon + 250-char description — doesn't justify the paradigm; whole Item story completes in one coherent stretch.

- **2026-05-17 → superseded 2026-05-18 — Pages editor shipped on native TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine`, NOT WKWebView.** Earlier decision (WKWebView + MarkEdit pattern + JSON bridge + Tiptap) was attempted via a Pallepadehat fork during v0.2.7 prep and abandoned — didn't deliver the macOS-native feel (Writing Tools, Look Up, Translate, spell-check, IME, dynamic system colors). Locked: **native NSTextView + TextKit 2 + Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine` (Apache 2.0, `External/MarkdownEngine/`)** + Pommora-side `AppleASTSupplementalStyler`. Shipped at v0.2.7.0 (`9a0b383`). Detail → `// Features//PageEditor.md`. `.md` format remains the firewall — future engine swap is reversible without user data migration.

- **2026-05-17 → revised — Pages + NavDropdown ship as v0.2.x patches. Final sequence:** v0.2.7.0 = Pages editor (shipped); v0.2.7.1 = NavDropdown (shipped, supersedes the earlier v0.2.7.2 first-attempt); v0.2.7.2 = page editor fixes (HR + lists shipped; Blockquote + Tables deferred). v0.2.9 (directives + heading fold + slash menu) **unscheduled** at RC-2026-05-19 — page editor is functional without them. v0.2.10 wikilinks **moved to v0.3.2** (couples with SQLite at v0.3.3 for indexed autocomplete + rename cascade). v0.3.0 = Properties.

- **2026-05-17 end-of-session — Agenda UI ships hand-in-hand with EventKit at v0.6.0 — NOT split.** Earlier in session, Agenda UI was provisionally pulled forward to v0.5.0 as a UI-only split. Reverted: they go together at v0.6.0. v0.6.0 consolidates Hardening + accessibility + performance + onboarding + Settings + accent customization. Calendar view in Saved section also ships at v0.6.0. Rationale: Agenda's full UI (time-field collapsing, calendar grid, EventKit-mirrored events) is interlocked — splitting creates two half-features.

- **2026-05-22 — ParadigmV2 symmetric operational-layer model.** Vault becomes Pages-only as "Page Type" with sidecar renamed `_vault.json` → `_schema.json`. New "Item Type" struct parallels Page Type for the Items side; "Item Collection" parallels "Page Collection." Schema sidecars unify to `_schema.json` everywhere. Items move from `<vault>/<collection>/item.json` to `<nexus>/Items/<type>/<collection>/item.json`. AgendaItem splits into AgendaTask + AgendaEvent with separate file extensions and schemas. Sub-topics renames to Projects (`.subtopic.json` → `.project.json`). On-disk wrapper folders `<nexus>/Pages/` and `<nexus>/Items/` introduced. UI label divergence: Page Types render as "Vault" (Pages-side default); Item Collections render as "Set" (Items-side default); code and data always say "PageType" / "PageCollection" / "ItemType" / "ItemCollection"; all UI labels renameable via Settings scaffold. Retires `Pommora.Collection` quirk #6.

- **2026-05-22 — Agenda Task/Event split locked.** Agenda becomes two distinct entities: AgendaTask (EKReminder-shaped) and AgendaEvent (EKEvent-shaped). Separate file extensions (`.task.json` / `.event.json`), separate schemas (`<nexus>/Agenda/Tasks/_schema.json` + `<nexus>/Agenda/Events/_schema.json`), separate managers (`AgendaTaskManager` / `AgendaEventManager`). Swift type names are `AgendaTask` and `AgendaEvent` (prefixed to avoid `_Concurrency.Task` and `Event` stdlib collisions); UI labels remain "Task" and "Event" by default (renameable via Settings). Status property is built-in required on AgendaTask schema (EventKit-aligned 3-group); NOT on AgendaEvent schema.

- **2026-05-22 — "Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for module name (`Pommora` Swift module), app branding, documentation. NOT allowed in JSON field names (no `pommora_*` keys) or as a Swift type qualification (`Pommora.X`) workaround for collisions. Side-prefixed names are the canonical pattern for collision resolution (`AgendaTask` not `Pommora.Task`). Existing `pommora_table_widths` (page editor frontmatter key) grandfathered for v0.3.0; rename when Tables ship.

- **2026-05-22 — Settings scaffold introduces `.nexus/settings.json` as the per-Nexus user-preference store.** Carries accent color + UI labels for all renameable surfaces (sidebar sections, Type labels, Collection labels per side, Project, AgendaTask, AgendaEvent). SettingsManager is the single read source for UI label sites — every label-rendering view reads from `settingsManager.labels.X` rather than hardcoded strings. Existing `.nexus/tier-config.json` and `.nexus/saved-config.json` stay separate (consolidation reserved for v0.6.0). Settings editing UI ships v0.6.0; v0.3.0 scope is storage + manager + label wiring + stub Settings scene reachable via Cmd+,. SettingsManager instantiated in `ContentView.constructManagers`, NOT in `PommoraApp` (correctness fix surfaced in audit) — needs the active-Nexus URL which only ContentView holds.

- **2026-05-22 — UI label divergence locked.** Pages-side UI renders as **"Vault"** (PageType) / **"Collection"** (PageCollection). Items-side UI renders as **"Type"** (ItemType) / **"Set"** (ItemCollection). The code layer stays universally Type / Collection (PageType, PageCollection, ItemType, ItemCollection — no Swift renames). The asymmetry intentionally gives each side one signature word + one shared word, making the vocabulary visibly distinct without echoing across sides. Sidebar order locked: Items above Pages (quicker-capture entities ride higher). No dedicated Agenda sidebar section — Agenda Tasks + Agenda Events surface via the Calendar pin entry.
