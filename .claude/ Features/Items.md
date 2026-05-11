### Items

An Item is a **lightweight row-shaped entry inside a Collection**. Properties + relations + a short description — no Markdown body. For database entries that don't warrant a full Page: wishlist entries, quick ideas, reference list items, tasks without notes.

Items solve the Notion problem of every database row being a full page. In Notion, a wishlist line and a life domain are both Pages; in Pommora, the wishlist line is an Item and the life domain is a Page.

---

#### On disk

JSON entries inside their Collection's `_items.json` sidecar (alongside `_collection.json`). The `_items.json` file is absent if the Collection has no Items yet; created on first Item add.

Full file shape and entry schema → `Collections.md` (`_items.json` schema section).

Each Item entry carries:

- `id` — ULID, stable across renames (target of relations)
- `name` — Item's title equivalent (Items have no filename; `name` plays the title role)
- `description` — short plain-text field, one-line context. Not Markdown, not a body.
- `icon` — optional, same catalog as Pages and Collections
- `properties` — values conforming to the Collection's schema (same property catalog as Pages)
- `spaces` — Space ID multi-relation (Items can appear on Space homepages like Pages can)
- `created_at` / `modified_at` — UNIX timestamps, auto-managed

---

#### Page vs. Item — choosing

The decision is content-shape, not data-shape. Both can hold the same properties and relations.

- **Page** if the entry has a body you'll write or read — notes, project briefs, journal entries.
- **Item** if the entry is fundamentally a row — properties and maybe a short description, no body.

If an Item later outgrows its row-shape (you keep wanting to add notes), promoting it to a Page is a likely v1.1 quality-of-life feature; preserving `id` keeps inbound relations intact.

---

#### Capabilities

- Hold typed properties from the Collection's schema (same catalog as Pages; full type list → `Properties.md`)
- Hold typed relations to any other entity in the vault (Pages, Items, Collections, Spaces) by ID — rename-safe
- Appear in the Collection's views (table / board / list / cards / gallery) alongside Pages. Views can show pages-only, items-only, or both via a `members` field; default is both.
- Appear on Space homepages via the `spaces` field, the same way Pages do
- Be linked-to from a Space's link-list widget or referenced by an embedded Collection view

---

#### Editor surface

Items have no prose editor. Opening an Item shows its property panel (typed inputs for each schema property) plus the `name` and `description` fields. No body, no blocks, no `@Columns`. If the entry needs a body, it should be a Page.

---

#### Constraints

- An Item belongs to **exactly one Collection** — no loose form. The only way to have a row-shaped entry without a Collection is to make it a Page (which can be loose).
- No multi-Collection membership.
- No ad-hoc properties (same rule as Pages: properties must come from the Collection's schema).
- The `name` field cannot be empty — it's the Item's title equivalent.

---

#### Why Items exist

The thesis: Notion conflates "row in a database" with "page with a body" because every database entry is a full page. Pommora keeps them distinct. Pages are for entries that warrant prose; Items are for entries that don't. This:

- Keeps the vault scannable (Markdown files are entries with bodies; Items live in a single JSON sidecar per Collection)
- Maps cleanly to cloud sync (`pages` table and `items` table both keyed by `collection_id`)
- Preserves file-canonical access — `_items.json` is plain JSON any agent or text editor can read
- Stays compatible with the agent-legibility principle (PRD: Persistent Immediate Legibility for Agents) — an agent reads the file and gets all Item rows + properties + relations in one parse
