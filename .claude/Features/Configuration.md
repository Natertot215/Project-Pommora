### Configuration

How a Nexus and the app get personalized. Two scopes: a per-Nexus layer in `.nexus/settings.json` — **personalization**, **labels**, and the profile (image + subtitle) — that travels with the Nexus and syncs, and a per-device **app config** that stays on the machine. A third scope — transient device-local UI state (folds, active view, view order, table headings) — is never synced and lives with the read engine (→ `Architecture.md`).

### Personalization (per-Nexus)

Nexus-wide interface config, stored as the React-owned `personalization` object in `.nexus/settings.json` (canonical, synced). It resolves through one schema, one **apply-map** (each knob → a CSS variable, a root class, or a value the renderer reads), and one generic setter — so a new knob is a schema field plus an apply-map row, nothing more.

#### II. Knobs

- **accent** — the app-wide accent: a spectrum solid, or `system` to follow the OS. Back-compatible with the legacy top-level `accent_color`.
- **connectionColor** — the inline `[[Title]]` connection colour; defaults to the accent (tracking it live) or pins a specific solid.
- **hideChevrons** — collapse the sidebar's disclosure-chevron gutter.
- **outlinerLines** — nested-list indent rails in MarkdownPM.
- **defaultIcons** — the per-kind default icon (Collection / Set / Area / Topic / Project / Page), overriding the built-in seed; an entity's own icon still wins over it.
- **setPlacement / subSetPlacement** — the value names where the FOLDERS sit, never the pages: a Collection's depth-1 Sets (`setPlacement`) and a Set's Sub-Sets (`subSetPlacement`) sit above (`top`, default) or below (`bottom`) their container's loose pages — so "pages on top" is spelled `bottom`. The knobs are independent tiers: `setPlacement` never moves a Set's own pages (a Collection with no loose pages shows no visible change), and set-level pages answer only to `subSetPlacement`. The folder block stays contiguous — a full folder↔page interleave is the eventual model. Read-side only: no UI writes these keys yet — they're set by editing `settings.json` directly, and the watcher applies the change live.

#### II. Write Discipline

Every `settings.json` write funnels through one per-file serialize lock (the same lock the page-write path uses), so concurrent writers can't drop each other's keys. Unrecognized keys are preserved by value on write, so a key one build doesn't know — desktop ↔ mobile version skew — survives the round-trip.

### Labels (per-Nexus)

Every entity kind carries a **renameable display label** in `settings.json` (`labels.*`, synced) — the code identity is fixed, the shown name is the user's. Each is a **LabelPair** (singular + plural): the sidebar section headers derive from the plurals, and the deeper-Set label is derived as `"Sub-" + Set.singular`, never stored. A partial or absent `labels` blob falls back per field, so an unset name still resolves to its default. Each of these pairs can have both their singular and plural identification labels renamed on the user-facing level -- their code-facing names adhere to these defaults regardless. 

Seven pairs, defaulting to:

- **Contexts** — Area -> Areas · Topic -> Topics · Project -> Projects.
- **Pages** — Collection -> Collections · Set -> Sets.
- **Agenda** — Task -> Tasks · Event -> Events.

### App Config (per-device)

Cross-session, machine-local state in `pommora.json` under the app's userData directory: the last-opened Nexus, the recents list, and the delete target (in-Nexus trash vs the system trash). It is never part of a Nexus, so it never syncs.

### Pending

**Settings Editing UI:** The personalization block has a setter and a live apply-map but no UI — accent, connection colour, and the toggles are set in `.nexus/settings.json` directly for now. A picker/toggle surface, also covering labels and profile, is planned.
