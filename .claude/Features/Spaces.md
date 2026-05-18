### Spaces

**Spaces are now tier-1 Contexts.** This doc is retained as a stub redirect — the full spec for Spaces (and Topics, Sub-topics, and the Contexts tier system) lives in `Contexts.md`.

The earlier model — Spaces as standalone composed-page entities holding `.space.json` files — has been replaced. Spaces still have composed-blocks pages (the `blocks` field shape is unchanged); the structural change is that Spaces are now the top tier of the Contexts hierarchy, and Topics + Sub-topics share the same composed-page surface pattern.

For the singleton dashboard surface (the user's general home page that can embed anything), see `Homepage.md`.

→ `Contexts.md` — full spec for Spaces, Topics, Sub-topics
→ `Homepage.md` — singleton dashboard entity
→ `// Planning//Contexts-Vaults-spec.md` — complete on-disk schema + CRUD
