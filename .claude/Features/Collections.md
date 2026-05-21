### Collections

**Collections are now sub-folders inside Vaults.** This doc is retained as a stub redirect — the full spec for Vaults, Collections, and Content lives in `Vaults.md`.

The earlier model — Collections as standalone typed-at-creation entities (`kind: pages | items`) holding `_collection.json` — has been replaced. The new model:

- **Vaults** are the schema-bearing folder entity (`<nexus>/<Vault>/_vault.json`)
- **Collections** are sub-folders inside Vaults, sharing the Vault's schema. They carry a minimal `_collection.json` sidecar (`{id, vault_id, modified_at}`) for stable identity across renames (paradigm decision 2026-05-16)
- **Content** (Pages + Items) lives inside Collections (or directly inside the Vault)
- Vaults are kind-agnostic — Pages and Items can coexist in the same Vault under the shared schema

Collection-local schema overrides are a post-v1 Prospect (see `Prospects.md`).

→ `Vaults.md` — full spec for the operational-layer containment unit
→ `Pages.md` — Markdown-bearing Content
→ `Items.md` — JSON row-shaped Content
→ `// Planning//Contexts-Vaults-spec.md` — complete on-disk schema + CRUD
