### Prospects

> Potential features. Not in immediate scope; brainstormed ideas that we may build in the future. Items here aren't committed to any specific version — they're the ongoing wishlist. Items get pulled out of Prospects and into `Framework.md` when they become committed work.

#### Format

Each prospect uses the format below. Easy to add new entries: copy the template, fill in the description.

```
#### Feature name
**Description:** 1-4 sentences. Bullets allowed if useful.
```

---

#### Independent UI titles (non-local naming)
**Description:** Allow a Page's display title in the UI to differ from its filename on disk. v1 ties title strictly to filename — renaming the title in the UI renames the file. North-star feature for later; could be implemented as an opt-in alias layer in frontmatter without changing the file-as-source-of-truth principle.

#### In-line view embeds (`@View`) inside Pages
**Description:** Embed a Collection view directly inside a Page's prose via the `@View` directive — Notion-style. Embedded Collection views remain available *inside Spaces* (as widget blocks) for v1; this prospect is about extending them inline into Pages.

**For React**

An `@View` directive becomes a custom block component on top of BlockNote core — well-trodden territory.

**For Swift**

Embedding a custom view inside the native `TextEditor` is not supported; would require an `NSTextView` / TextKit 2 surface (real AppKit work). The v2+ revisit is React-conditional for this reason.

#### Ad-hoc page-local properties
**Description:** Allow a Page to declare properties not in its Collection's schema (Obsidian-flavor flexibility). v1 enforces schema conformance — every property on a Page must come from the Collection. The only "outside the schema" thing for v1 is sidebar ordering / sorting, which is UI state and lives outside file content.

#### Cloud sync (Supabase or otherwise)
**Description:** Additive translation layer that maps the local file model to a cloud database. The mapping mirrors the local SQLite shape (matching Notion / Airtable / AFFiNE convention): a single shared `pages` table where each row carries `collection_id` and a `properties` JSONB column; each `_collection.json` schema → a row in a `collections` table; each Space → one row in a `spaces` table with the block tree as a JSON column. v1's on-disk model is designed to make this non-disruptive when it arrives — sync becomes pure translation, not redesign.

#### Mobile companion (iOS / iPad)
**Description:** Read and edit access to the vault from mobile devices. iPad is the most plausible "Pommora elsewhere" target.

**For React**

A separate effort — Capacitor wrapper or a parallel native build. The shared TypeScript Core layer helps but the UI is not portable to mobile-native paradigms.

**For Swift**

Essentially free — the same Swift Package codebase ships to iPad and iOS with platform adaptations. The natural growth path on this stack.

