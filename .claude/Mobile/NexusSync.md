## Mobile — Sync

How the companion shares one nexus with the desktop. The model is deliberately simple, and the simplicity is a decision, not a limitation.

### The Single-User Premise

Pommora is personal-first and used from one location at a time — a person cannot edit on two devices simultaneously. The sync model follows directly: **most-recent-wins**, with no merge, no conflict-resolution interface, and no collaboration machinery. The phone is a full editor with the same abilities as the desktop; it is not scoped down to avoid conflicts, because for a single sequential user the conflicts that scoping would prevent don't arise.

### Transport — iCloud Drive

The nexus lives in iCloud Drive; the desktop writes it, the phone reads and writes the same files. iCloud syncs by a file's location, not by which app wrote it, so the desktop side needs no special entitlement or native iCloud code — plain filesystem writes into an iCloud-synced folder propagate on their own. Sync rides the user's Apple ID; there is no account and no login.

The nexus lives in an **app-owned iCloud container** — Pommora registers its own container and the nexus lives at a fixed `iCloud Drive/Pommora/`, exactly the way Obsidian syncs a vault. The phone reaches it directly: no folder picker, no bookmark lifecycle, auto-discovered, and still visible in the Files app. This is the v1 shape — the least code on the phone, and all a companion needs, since it only ever reaches the one synced nexus.

Opening an **arbitrary user-picked folder** (any iCloud folder, in place — including an existing Obsidian vault) is a logged Prospect, not v1: allowed later as an additive capability, not designed around now. It would also let a mobile-rooted folder be the origin the desktop syncs to, rather than assuming the desktop is always the source. To keep it cheap to add, the custom filesystem plugin resolves its folder behind a seam — the container is one resolver; a picker-plus-bookmark is a second that slots in without touching the read, write, or materialize core. A picked folder still syncs like any other, so this never introduces a non-synced nexus.

Either shape needs the iCloud capability and container declared in Xcode (the paid Developer Program), and the Files-app sharing flags enabled so the nexus stays user-visible and agent-legible on the phone rather than trapped in a private sandbox.

### Ingestion — the Watcher Already Handles It

The desktop's file-watcher is **origin-blind by design**: on any on-disk change it re-reads the tree and refreshes, without caring whether the app or something external wrote the file. It was built so external edits — Obsidian, Finder — flow in without a restart, and an iCloud change arriving from the phone is, to this code, exactly that: an external edit. The sync-ingestion path already exists, and the same holds in reverse on the phone.

Two things the watcher was not originally built for, both addressed on the mobile read path:

- It re-reads the whole tree on each settle. On a large nexus every read is an iCloud read, so the mobile read path must be lazy rather than eagerly walking everything.
- It assumes local, instantly-complete writes. iCloud writes arrive over seconds, and iCloud evicts file contents to placeholder stubs — see the materialization gate below.

### The Necessary Precautions

For a single user, only a few safeguards are actually required; everything beyond them is over-engineering for a collaboration scenario that doesn't exist.

- **Atomic writes — already in place.** Every write goes to a temporary sibling and atomically renames over the target, so iCloud never uploads a half-written file. The JSON serializer is byte-stable, so re-saving unchanged data produces identical bytes and no spurious sync.
- **The materialization gate.** iCloud evicts a file's contents to a placeholder while leaving the file apparently present; a naive read then returns nothing. On the phone especially, the read path must detect an un-downloaded file, trigger its download, and show a downloading state before parsing. A blank note here is an un-materialized file, not a broken one. The gate lives in a **staged read path** — a cheap structure-only pass plus lazy per-entity download — not inside the desktop's single eager tree-walk, which would otherwise materialize the whole nexus on every launch and every synced change (see `MobileArchitecture.md`).
- **Conflict-copy dedupe.** If the same page is edited on two devices while one is offline, iCloud itself forks a duplicate copy. Because every entity carries a stable id, the app keeps the newest by modification time and discards the fork, so a conflict copy never surfaces as a ghost duplicate. This is most-recent-wins applied to the one artifact iCloud creates on its own — the entire extent of conflict handling.
- **Sync the whole nexus, minus a few per-machine display files.** Almost everything is shared and must sync — page files, sidecars, and nearly all of `.nexus/`, which holds the property registry, the Contexts, the Homepage, settings, and image assets. Only four `.nexus/` files are per-machine display state and should not sync: heading-folds, active-view pointers, per-view row orders, and table-heading-column flags. Excluding the `.nexus/` folder wholesale would strip the schema, Contexts, Homepage, and images from the phone — the exclusion is **per-file, never per-folder**. (`state.json` is fully canonical in this build — it holds only the top-level order keys — so it syncs whole, no special-casing.)

The in-process write lock the desktop uses to serialize overlapping edits within one running app is single-device only; it plays no part in cross-device sync, which is iCloud's job.

### Cascades and Eventual Consistency

Some operations touch many files at once — renaming a page rewrites every inbound link across the nexus; deleting a Context strips its id from every page that referenced it. Each file is written independently, and over iCloud those writes propagate one at a time and out of order. During propagation the receiving device can briefly see a half-applied state, and because connections resolve by title, some links are momentarily unresolved. This is invisible to a single user who isn't watching the other device mid-sync, and it self-heals once the last file lands. Eventual consistency is the accepted behavior; no special settle step is added.

### The Index Stays Local

The SQLite index is a regeneratable accelerator, never a source of truth. It is excluded from sync and rebuilt per device — a binary database syncing across devices invites corruption and churn, and there is nothing in it the canonical files don't already hold.

### When iCloud Isn't There

The phone's data access is iCloud, so the states where it isn't ready are first-class, not edge cases. On first launch the app confirms the user is signed into iCloud and the container is provisioned — if not, it says so plainly rather than presenting an empty nexus as if the data were gone. A file mid-download shows a downloading state (the materialization gate); a nexus not yet fully synced shows what has arrived and fills in as more lands. None of this is a conflict or an error — it is the normal shape of opportunistic sync, and the UI names it rather than looking broken.
