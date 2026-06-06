## Planning — Index

Active plan documents live here at the top level; the `Superseded/` sub-folder archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then either moved to `Superseded/` or removed; never leave a stale plan presenting as active.

Plans are named `MM-DD-<slug>.md` (earlier files retain their `YYYY-MM-DD-` names). They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

#### Active

- `06-03-ItemsV2-Implemented.md` — **as-built spec** for the SHIPPED Items redesign (single config-driven floating `ItemWindowRenderer`; `LayoutArchetype` enum + `template_config` on Type+Collection; native floating scene + `PreviewWindow` replacing the deleted `.sheet`; Templates settings pane; Type→Collection override; 500-char cap). What EXISTS. Companion execution record: `06-03-ItemsV2-Plan.md` (30 tasks, all green).
- `06-03-ItemsV2-Planned.md` — **DESIGN-ONLY** next rework (2026-06-03 Figma brainstorm): retires `LayoutArchetype` for a fixed type-bound **zone framework** — templates assign capped schema properties into zones, layout emerges, live window becomes a display-only stub first. What's NEXT, not built. Item Chips (`{{ }}` item connections) are spec'd in `Features/Connections.md`.
- `2026-06-03-Folder-Exclusion-Plan.md` — vault-owned, user-configurable folder exclusion: an `excluded_folders` list on `.nexus/settings.json` honored by a single per-Nexus `FolderFilter` veto across both discovery passes (index rebuild + manager `loadAll`), adoption, and content roll-up; `.nexus/` internal Context reads stay exempt. 7 bite-sized TDD tasks; matching is anchored vault-relative + case-insensitive/NFC (git model, not Obsidian substring). Built on a 5-agent research sweep (discovery surface + settings/sequencing + test landscape + FileManager/APFS semantics + gitignore-style design).
- `2026-06-02-MarkdownPM-Plan.md` — the **finalized** MarkdownPM rebuild implementation plan: fold the vendored `MarkdownEngine` into a Pommora-owned `MarkdownPM` package; one cached Apple-AST parse spine (the #9 fix); delete the hand-rolled emphasis parser; merge the dual styler into one owned styler + `MarkdownPMTheme`; transplant the runtime-only TextKit 2 workarounds verbatim. **Pages-only** (Items excluded; wikilinks = separate post-rebuild session). Full bite-sized TDD for Phases 1–3, concrete outline for 4–6; Nathan's rulings folded in as `Locked Decisions` (LD-1..LD-32). Validated through 3 adversarial review rounds (blocker→cosmetic convergence).
- `2026-05-31-vault-table-displayonly-interim.md` — interim spec for display-only Type detail tables + creation-order default (shipped v0.3.4).

#### Superseded

`Superseded/` archives plans that have fully shipped or been abandoned.

- `Superseded/2026-06-02-MarkdownPM-Service.md` — the v2 design/altitude doc for the MarkdownPM rebuild; superseded by the finalized `2026-06-02-MarkdownPM-Plan.md` (phase intent preserved there; the v2 doc's claims were re-verified + corrected by the CodeMap). The separate 26-decision surface (`MarkdownPM-Decisions.md`) was folded into the plan's `Locked Decisions` and removed.
- `Superseded/2026-06-01-Items-as-Markdown-Plan.md` — convert Items from whole-`.json` to plain `.md` (Shape A; one `AtomicYAMLMarkdown` pipeline; folder-sidecar kind authority; foreign-key preservation; auto-run migration). SHIPPED 2026-06-02 (1153/1153 green); ratified as registry decision #14, logged in `History.md`.
