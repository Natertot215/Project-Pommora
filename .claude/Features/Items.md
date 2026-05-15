### Items

An Item is a **row-shaped record** stored as a `.json` file. Properties + relations + a 250-character plain-text description, opened in an **Item window** (popover-style — Calendar-event-detail pattern). For database entries that don't warrant a full Page: tasks, wishlist entries, contacts, events, references. No Markdown body, no tab, no full page.

Items solve the Notion problem of every database row being a full page. The kind split lives at the Collection level (see `Collections.md`): a Collection is either an Items collection or a Pages collection, set at creation. Member Items live inside an Items collection's folder; **loose Items** live anywhere outside Collection folders and carry only built-in fields (no schema-conforming properties).

---

#### On disk

**One `.json` file per Item.** Filename = title (same rule as Pages). Member Items live inside an Items collection's folder; loose Items live anywhere outside Collection folders. No aggregate file, no nested `items//` subfolder.

```
Tasks//                     ← Items collection
  _collection.json          ← "kind": "items"
  Buy groceries.json        ← member Item (schema-conforming properties)
  Fix sink.json
  Steam Deck OLED.json

Bookmark.json               ← loose Item in nexus root (built-in fields only, no properties)
Inbox//                     ← cosmetic folder (no _collection.json)
  Quick reference.json      ← loose Item
```

Renaming an Item in the UI renames the `.json` file on disk. Inbound relations stay intact because relations are by `id`, not by name.

Each Item file holds:

- `id` — ULID, stable across renames (target of relations)
- `description` — plain-text field, **hard cap 250 characters**. Sized so the field fits within the Item window without scrolling. Not Markdown, not a body.
- `icon` — optional, same catalog as Pages and Collections
- `properties` — values conforming to the Collection's schema (same property catalog as Pages)
- `spaces` — Space ID multi-relation (Items can appear on Space homepages like Pages can)
- `created_at` / `modified_at` — UNIX timestamps, auto-managed

No `name` field — the filename IS the name (consistent with Pages, where filename IS the title).

---

#### Choosing the Collection's kind

The decision happens at Collection creation, not per-entry. Each Collection is uniformly either Items or Pages.

- **Items collection** — every member is a row: properties and maybe a short description, no body. Tasks, contacts, wishlist, events, citations, music releases, recipes-as-rows.
- **Pages collection** — every member has prose: notes, papers, project briefs, journal entries, reading reports, write-ups.

If an entry inside an Items collection later needs prose, it doesn't get "promoted" to a Page in-place (v1 doesn't support that — see `Prospects.md`). Instead, create a Loose Page or a Page inside a different Pages collection, and link to the original Item by ID.

---

#### Capabilities

- Hold typed properties from the Collection's schema (same catalog as Pages; full type list → `Properties.md`)
- Hold typed relations to any other entity in the nexus (Pages, Items, Collections, Spaces) by ID — rename-safe
- Appear in the Collection's views (table / board / list / cards / gallery). Views in an Items collection show its Item rows uniformly — no per-view member-kind filter needed.
- Appear on Space homepages via the `spaces` field, the same way Pages do
- Be linked-to from a Space's link-list widget or referenced by an embedded Collection view

---

#### Item window

Items don't have a prose editor; they open in an **Item window** — a popover-style floating surface anchored to the trigger (sidebar click, table cell, wikilink, embedded-view row). Reference pattern: Calendar.app event-detail popover; macOS Finder's Get Info window. Not a tab, not a full page, not the inspector.

The window contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Properties** — typed inputs for each property in the parent Items collection's schema. Loose Items show no schema-conforming properties (only built-in fields).
- **Description** — plain-text field, **hard cap 250 characters**. Sized to fit the window without scrolling; keeps the JSON file small and cloud-sync-friendly.

Dismissed by clicking outside, pressing Esc, or closing the window. No body, no blocks, no `@Columns`. If the entry needs a body, it should be a Page.

---

#### Constraints

- A member Item belongs to **exactly one Items collection**. Loose Items belong to no Collection and carry no schema-conforming properties. No multi-Collection membership.
- An Items collection only holds Items (no `.md` Pages in the same folder). A Pages collection only holds Pages. `.md` or `.json` in the wrong-kind Collection folder is a nexus-integrity warning.
- No ad-hoc properties on members (properties must come from the Collection's schema). Loose Items have no schema at all.
- The Item's filename cannot be empty — it's the title equivalent (same as Pages).
- No in-place promotion to Page in v1 (see `Prospects.md`).

---

#### Why Items exist

Notion conflates "row in a database" with "page with a body" because every database entry is a full page. Pommora keeps them distinct and lifts the distinction to the Collection level — a Collection is either prose-bearing or row-shaped, never mixed. This keeps the nexus scannable (an Items collection folder is uniformly `.json`; a Pages collection folder is uniformly `.md`), maps cleanly to cloud sync (parallel `pages` / `items` tables keyed by `collection_id`), preserves file-canonical agent legibility (each Item is its own openable JSON file), and removes the per-entry "Page or Item?" decision Notion forces.
