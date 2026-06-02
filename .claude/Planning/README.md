## Planning — Index

Active plan documents live here at the top level; the `Superseded/` sub-folder archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then either moved to `Superseded/` or removed; never leave a stale plan presenting as active.

Plans are named `YYYY-MM-DD-<slug>.md`. They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

#### Active

- `2026-06-01-Architecture-Skeptic-Review.md` — adversarial review of the storage/architecture model; recommendation #3 superseded by the Items-as-Markdown decision.
- `2026-05-31-vault-table-displayonly-interim.md` — interim spec for display-only Type detail tables + creation-order default (shipped v0.3.4).

#### Superseded

`Superseded/` archives plans that have fully shipped or been abandoned.

- `Superseded/2026-06-01-Items-as-Markdown-Plan.md` — convert Items from whole-`.json` to plain `.md` (Shape A; one `AtomicYAMLMarkdown` pipeline; folder-sidecar kind authority; foreign-key preservation; auto-run migration). SHIPPED 2026-06-02 (1153/1153 green); ratified as registry decision #14, logged in `History.md`.
