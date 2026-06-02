## Planning — Index

Active plan documents live here at the top level; the `Superseded/` sub-folder archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then either moved to `Superseded/` or removed; never leave a stale plan presenting as active.

Plans are named `YYYY-MM-DD-<slug>.md`. They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

#### Active

- `2026-06-02-MarkdownPM-Service.md` — fold the vendored `MarkdownEngine` into a Pommora-owned `MarkdownPM` Swift package: consolidate the dual parser/styler onto one cached Apple-AST spine with strict DRY, transplant the TextKit 2 body verbatim, **Pages-scoped** (Items excluded; wikilinks = separate post-rebuild session). Provisional scaffolding pending the finalized plan.
- `2026-06-02-MarkdownPM-Decisions.md` — the 26-decision surface for the MarkdownPM rebuild + Nathan's locked rulings (2026-06-02).
- `2026-05-31-vault-table-displayonly-interim.md` — interim spec for display-only Type detail tables + creation-order default (shipped v0.3.4).

#### Superseded

`Superseded/` archives plans that have fully shipped or been abandoned.

- `Superseded/2026-06-01-Items-as-Markdown-Plan.md` — convert Items from whole-`.json` to plain `.md` (Shape A; one `AtomicYAMLMarkdown` pipeline; folder-sidecar kind authority; foreign-key preservation; auto-run migration). SHIPPED 2026-06-02 (1153/1153 green); ratified as registry decision #14, logged in `History.md`.
