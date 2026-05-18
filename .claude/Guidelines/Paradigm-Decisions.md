### Paradigm Decisions

Pommora's value depends on its on-disk format, schemas, and cross-entity contracts surviving a stack rebuild and a future cloud sync (load-bearing constraints #1 and #2). Code that locks in those shapes is **paradigm-solidifying** — once data exists in the wild written by it, migrating is expensive.

#### Operating rule

When implementing code that solidifies a paradigm choice, **stop and surface the choice for Nathan's confirmation before the code lands**. Not after. Not in passing as a "by the way." Use `AskUserQuestion` with concrete trade-offs and your recommendation.

This applies even when a written plan or spec already proposes one path — if the choice is paradigm-solidifying and you spot ambiguity, a real downside, or an alternative worth weighing, surface it first. Spec drift is acceptable; silent commitment is not.

#### What counts as paradigm-solidifying

- **On-disk schema shapes** — fields, types, naming conventions, snake_case vs camelCase per-key choices, nesting structures inside `_vault.json` / `.space.json` / `.agenda.json` / etc.
- **Wire encodings for ambiguous types** — tagged-object vs bare-string discrimination (e.g. `.relation` vs `.select` strings), date format choices (ISO-8601 vs Unix epoch vs human-readable), null-vs-missing semantics.
- **Identifier conventions** — ULID format, filename-as-title rule, ID-vs-title display split, relation key shape (e.g. `{"$rel": "..."}`).
- **Default values that become locked once data exists** — seeded `_agenda.json` schema, `defaultSeed()` outputs for TierConfig / SavedConfig / Homepage, default property catalog per Vault.
- **File layout choices** — folder vs file boundaries for entities, filename extension conventions (`.subtopic.json` vs `_subtopic.json`), sidecar metadata file naming (`_vault.json` vs `vault.meta.json`).
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
2. **State the choice in user-facing terms** — "what does this mean in practice for what's on disk / what users see / what migrations would cost?" — not in implementation jargon.
3. **Present 2-3 options** with concrete on-disk samples or behavioral examples. Lead with your recommendation.
4. **Wait for confirmation.** Update the spec/plan to reflect the locked choice before dispatching implementation.
5. **Record the locked decision** in this file's "Confirmed decisions" registry below (or in `History.md` if more substantial) so future sessions don't re-litigate.

#### Confirmed decisions

A short registry of paradigm decisions that have been locked via this protocol. Each entry: date, decision, rationale-in-one-sentence.

- **2026-05-16 — `PropertyValue.relation` encodes as tagged object `{"$rel": "<ULID>"}`.** Bare-string `.relation` and `.select` are indistinguishable; tagged-object encoding makes relation edges legible to external agents and the graph-view indexer without consulting Vault schema (satisfies load-bearing constraint #3).
- **2026-05-16 — Collections persist a minimal `_collection.json` sidecar at `<nexus>/<Vault>/<Collection>/_collection.json`.** Shape: `{id: ULID, vault_id: ULID, modified_at: ISO-8601}`. Collection becomes Codable. Making the parent-Vault relation an explicit on-disk property keeps external query/parsing tools from having to infer it from filesystem nesting, and gives Collections stable portable IDs (replacing the SHA-256 path-hash fallback).
- **2026-05-16 — SF Symbol picker uses `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's own `IconPickerSheet` view.** Wrapping isolates call sites from the third-party API surface — swapping libraries (or moving to a hand-rolled grid) is a single-file rewrite in the wrapper, no call-site churn.

- **2026-05-17 — Stub-and-progressively-replace execution strategy for branch-spanning plans.** When a plan's tasks have forward-dependencies on each other (row views reference enums defined in a later task; sheets reference manager methods defined in a later task), the spec's "defer commit until batch integration at the end" approach produces uncommitted N-task blobs where any single break contaminates the whole batch. Instead: write each task with throwaway in-file stubs for not-yet-shipped types (e.g. `SheetStubView` placeholder for sheet bodies, `SelectableRow` stub for row views), then later tasks replace the stubs in-place. Every commit ships green standalone, every commit is independently verifiable. The cleanup (stub removal) lives in a final task or rolls into the next dependent task. Applies to any plan with similar topology; **supersedes spec batch-commit instructions**.

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

- **2026-05-17 — Item creation surfacing deferred to v0.5 (bundled with Properties + Item Window redesign).** v0.2 ships with only one Item creation path (`CollectionDetailView` footer "+ New Item"); broader surfacing (Vault detail footer button + Vault/Collection row right-click `New Item` entries + Sidebar.md menu-table update) waits until v0.5. Rationale: an Item without Properties is just title + icon + 250-char description, which doesn't yet justify the Item paradigm — surfacing prominent creation entry points before Properties land would teach users a paradigm whose meaning changes under them when v0.5 arrives. The `.newItem(...)` sheet routing is already wired in `SidebarView` + `SidebarDetailView` from v0.2; v0.5 just hangs visible entry points off the existing routes. Cohesion-over-incrementalism call: the whole Item story (creation paths + property editing + Window redesign per Nathan's WIP sketch) ships together.

- **2026-05-17 — Pages editor architecture LOCKED; editor library NOT solidified.** (Demoted end-of-session 2026-05-17 from prior "Tiptap LOCKED" framing.) The **architecture** is: WKWebView + MarkEdit-pattern native shell + 7-message JSON bridge (`init`, `save`, `themeUpdate`, `query`, `queryResults`, `openWikilink`, `editorError`) + `WKURLSchemeHandler` for `pommora-editor://` bundle loading. JS owns editor state; Swift owns the file on disk; frontmatter never crosses the bridge. This architecture is stack-agnostic and survives any editor-library choice. **Editor library** — Tiptap (ProseMirror, vanilla TS, MIT) is the **leading candidate** but final pick reopens at v0.2.7 implementation start. Alternatives: Milkdown (ProseMirror, remark-based, near-perfect Markdown round-trip), BlockNote (React + multi-column GPL/commercial — likely rules out), CodeMirror 6 (source-with-decorations / Live Preview — paradigm switch). Swap effort if Tiptap is replaced: 1-2 days for sibling ProseMirror editors, 3-5 days for CodeMirror. Full implementation spec at `// Planning//Page-Editor-Plan.md`.
  - **What we give up if Tiptap (or any WYSIWYG editor) wins over CodeMirror**: no Live Preview / source-with-decorations; near-perfect not byte-perfect round-trip; can't put cursor inside wikilink syntax; auto-pair behavior changes meaning. Accepted per Nathan's direction.

- **2026-05-17 end-of-session — Pages + Tabs ship as v0.2.x patches, NOT v0.3.0 / v0.4.0 minor versions.** Initially structured as v0.3.0 = Pages editor (with internal phases a/b/c) + v0.4.0 = Tabs (separate minor). Restructured to ship as v0.2.x patches: v0.2.7 = Pages editor (prose + standard Markdown), v0.2.8 = Tabs, v0.2.9 = directives + heading fold + slash menu (Pages addition), v0.2.10 = wikilinks + rename cascade (Pages addition). **Order between v0.2.7 and v0.2.8 is interchangeable** — whichever ships first is `.7`, the other `.8`. v0.3.0 becomes Properties — the next substantial capability after Pommora is writable + multi-instance. Rationale: Pages and Tabs are tightly coupled (writing without tabs is a regression people notice immediately); shipping inside one patch family is more cohesive than spreading across two minor versions.

- **2026-05-17 end-of-session — Agenda UI ships hand-in-hand with EventKit at v0.6.0 — NOT split.** Earlier in the same session, Agenda UI was provisionally pulled forward to v0.5.0 as a "UI-only" split from EventKit (v0.8.0). Reverted at end-of-session: they go together at v0.6.0. The v0.6.0 release also consolidates Hardening + accessibility + performance + onboarding + Settings + accent customization. Calendar view in Saved section also ships at v0.6.0. Rationale: Agenda's full UI (time-field collapsing, calendar grid, EventKit-mirrored event surfaces) is interlocked enough that splitting them creates two half-features instead of one cohesive release.
