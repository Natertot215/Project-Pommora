### Symbols Guide

Iconography indirection on the React path. Components reference **semantic symbol roles** (`settings`, `add`, `delete`, `expand`, etc.); the active icon library is resolved at render time from a vault-local mapping file. **Material Symbols (outlined)** is the default; swapping to SF Symbols is a planned setting (not v1-committed) that flips a value rather than touching components.

> **Stack-conditional — React only.** SwiftUI uses SF Symbols natively via `Image(systemName:)`; no indirection layer needed.

---

#### The mapping file

`.pommora// symbols.json` inside the vault. **Seeded on first launch from the canonical icon role table in `// Planning//Figma Prompt.md`** (covers shell / chrome, common actions, entity kinds, sidebar sections, editor formatting, property types, views, and view controls). Format:

> **Symbol color tokens** — symbols have their own color tokens (`symbol// primary`, `symbol// muted`, `symbol// active`); default render is `symbol// muted`. Defined in the Figma file alongside other Variables. Components can bind a specific symbol slot to a different `symbol//` token without touching text or accent.
>
> **Initial-build placeholder.** Until specific icons are finalized per role, the Figma design system renders every symbol slot as the `crop_free` Material Symbol (a square frame outline). Replacing the placeholder with the role's real Material name is done in a round-2 pass; the role mapping in the table is the canonical record of what each placeholder represents.

```json
{
  "settings": {
    "useCase": "App and per-entity settings access",
    "material": "settings",
    "sf": "gearshape"
  },
  "add": {
    "useCase": "Create a new entity (Page, Item, Collection, Space)",
    "material": "add",
    "sf": "plus"
  },
  "delete": {
    "useCase": "Remove an entity or property",
    "material": "delete",
    "sf": "trash"
  }
}
```

Each entry:

- **Key** — the semantic symbol role (lowercase: `settings`, `add`, `addProperty`, `expand`, `collapse`).
- **`useCase`** — one-line description of what this symbol represents in the UI.
- **`material`** — the Material Symbols name (active by default).
- **`sf`** — the SF Symbols name (active when the swap toggle is on).

Single source of truth for icon ↔ library translation across the app.

---

#### Component pattern

Components don't hardcode `material.settings` or `sf.gearshape`. They call a hook:

```tsx
// Conceptual; final API TBD when implementation lands
const SettingsIcon = useSymbol("settings");
return <button>{SettingsIcon}</button>;
```

The hook reads `symbols.json` + the active library setting and returns the appropriate icon component. **No component file references Material or SF names directly** — every icon usage goes through a semantic role.

---

#### Swap toggle (planned)

A user setting (probably alongside Framework v0.12 in-app customization) flips the active library between Material and SF. Flipping re-resolves every component's icons at the next render. Until the toggle ships, Material renders.

---

#### Editing the mapping

The file lives in the vault, so the user can edit it directly: override a role's mappings, or add new semantic roles. Changes persist across re-installs and travel with iCloud / Dropbox sync.

Per-component icon overrides are **not** a feature — every icon usage resolves through the semantic role, not through a per-call override.
