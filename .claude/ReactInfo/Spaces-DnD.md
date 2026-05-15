### React Spaces Composer

`@dnd-kit/core` v6 + flat-array tree representation. The block JSON serialization discipline (Zod, atomic write, ULID per block) is stack-portable and applies on Swift too — see `// Features//Spaces.md`.

> **Status:** Reference. Swift uses `Codable` Block enum + `visfitness/reorderable` + `stevengharris/SplitView` per `// Features//Spaces.md`.

---

#### Spaces strategy

**Locked direction:** `@dnd-kit/core` v6 + flat-array `[id, depth, parentId]` tree representation.

- Cross-level drag (a block dragged into a `columns` child or out into the top-level vertical flow) requires the flat-array shape; nested arrays don't compose well with dnd-kit's sortable strategies
- One shared `<CollectionViewRenderer>` dispatcher renders embedded Collection views inside Spaces and standalone Collection pages — same component, two contexts (mirrors Notion's `child_database` block pattern)
- View-override (filter / sort / group at embed time) is data merged onto the saved-view spec at render time; the Collection's saved view isn't modified

**Block JSON serialization discipline:**

- Validate with Zod on load and save (catches schema drift early)
- Atomic write via `.tmp` + rename
- ULID per block (sortable, generation-friendly)
