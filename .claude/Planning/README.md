## Planning — Index

Active plan documents live here at the top level; the `Superseded/` sub-folder archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then either moved to `Superseded/` or removed (git history preserves removed plans); never leave a stale plan presenting as active.

Plans are named `MM-DD-<slug>.md` (earlier files retain their `YYYY-MM-DD-` names). They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

`Assets/` holds plan-referenced artifacts (currently `PagePreview-Figma-V8.jpg`, the confirmed PagePreview design frame referenced by the archived PagesV2 plan).

#### Active

- `06-10-Contexts-Decoupling-Spec.md` — ratified spec for the Contexts decoupling: Projects become free-standing tier-3 contexts, context→context relations fully reset, sidebar tier disclosure rows.
- `06-10-Contexts-Decoupling-Plan.md` — the adversarially-verified implementation plan (P1–P6): project decoupling, topic-parents strip, ContextsSection, folder layouts + schema v12, the grep-gated Space→Area rename (+ schema v13), spec-voice doc rewrite.
- `06-05-Connections-Plan.md` — the Connections implementation plan. Page-level work shipped at v0.3.5 (`History.md` § "Connections — page-level complete"); retained at top level pending the post-v0.4.0 connection-model layer it also scopes.
- `Contextv2.md` — the Drop-Relations→Contexts refactor plan. Shipped 2026-06-04 (registry decision #16); retained at top level pending archival review.

#### Superseded

- `Superseded/PagePreviewWindow.md` — the V9 real-window PagePreview rebuild (WindowGroup + restriction pass + shared compact inspector). **COMPLETE at v0.4.0** (987 tests green). Record → `History.md` § "v0.4.0".
- `Superseded/PagesV2.md` — the PagesV2 implementation plan (11 phases, P0–P10). **COMPLETE as of `c7f48c7`** (986 tests green): the one-entity collapse — `Item*` deleted, `[[` sole syntax, `PageType.open_in`, the in-window `PagePreview` card (rebuilt next morning as a real window — see `PagePreviewWindow.md`), band-3 user sidebar sections, index schema v11, and this doc sweep. Record → `History.md` § "PagesV2"; decision → registry #17.
- `Superseded/06-09-Items-Strip-Spec.md` — the zero-assumption spec that fed `PagesV2.md`.
- `Superseded/06-09-Items-Pages-Collapse-Evaluation.md` — the 6-agent evaluation behind the collapse decision (ratified 2026-06-09).
- The three ItemsV2 plan files (`06-07-ItemsV2-Plan-V3.md`, `06-07-ItemsV2-Spec-V5.md`, `06-03-ItemsV2-Implemented.md`) were superseded by PagesV2 and deleted in `caa236b` — git history preserves them.
- Older shipped plans (MarkdownPM rebuild, Items-as-Markdown, Folder Exclusion, display-only vault tables, View Settings, etc.) were removed from the tree in earlier doc sweeps (e.g. `1cf347f`) — git history preserves them; their ship records live in `History.md`.
