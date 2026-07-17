## Page Preview

The floating page window — a movable, resizable, fully-editable glass window that opens Pages without touching the main pane's selection, tabs, history, or recents (tab-neutral by construction). It is a semi-multi-tabbed mini-app: wiki-links clicked inside it open as tabs beside the origin instead of navigating away, and the whole tab set persists per origin across sessions. One preview exists at a time; a new summon overtakes the window in place.

### The Window

Chrome rides the shared floating-window engine (`design-system/interactions/FloatingWindow.tsx` — per-window-id geometry, bare-surface move allow-list, four corner resizes; size persists across opens, position opens centered). The material is the window-background glass, edge-to-edge with no inset ring; color and opacity are knobs on the window's root. The window opens and closes on a scale-fade (the disclosure token); content scrolls under a floating toolbar that owns no band of its own — the body is the one scroller, and the editor chain grows to its content instead of scrolling internally.

The toolbar: the scan glyph on the left promotes the page — it opens for real through the normal select while the window plays the **engulf**, a FLIP from the window's live rect onto the detail pane's (translate to its center, scale to its box, fade). Dismiss (X, Escape) plays the plain scale-out; the close reason threads through the store so a promote can never replay as a dismiss or vice versa. The right cluster is settings + inspector + X, with the settings/inspector pair riding the inspector pane's edge on the `--io` swallow (the main toolbar's contract) while X holds home.

**Titles morph into tabs.** A single-tab window shows the centered two-tone breadcrumb (trail tertiary, page crumb control, caption ramp). The second tab's birth collapses the title left into a standard icon-leading tab in a left-aligned strip; closing back to one tab returns the title the same way. The strip is built on the container-agnostic tab motion layer (`Tabs/tabStrip.css`) with its own overflow scroller + edge fade; tabs are caption-sized independent of the toolbar glyphs. No pins, no manual +: tabs are born from navigation only. Page tabs drag-reorder within the strip (the toolbar strip's SortableZone pattern; the map sentinel and closing ghosts stay out of the item set), and the new order persists with the set.

### The Tab Model

A pure model (`PagePreview/previewTabs.ts`) + store slice, deliberately separate from the app tabs' `tabsModel` (its last-tab close kills the *window*, never reseeds a NavView). Wiki-clicks dedup-focus an existing tab for the same page; closing the active tab falls to its left neighbor; closing the origin re-parents the window to the left-most surviving page tab; the last close kills the window. Tab switches slide the content on the preview's own slide stamp (the DetailPane view-slide read), and an open inspector rides the same keyframes — the tab slide and pane push are one motion.

### Persistence & Warmth

One synced sidecar (`.nexus/page-previews.json`) holds the NavWindow flavor's set, the per-origin page sets (re-keyed to the new origin on re-parent; an emptied set retires), and the open pointer (recorded, never auto-summoned at launch). Restores reconcile against the live tree before showing — dead paths drop, renames re-path, an emptied set falls back to the bare origin. It rides the shared debounced-sidecar machine (`main/io/debouncedSidecar.ts` — the tabs/nav-recents contract) and drains at quit + nexus switch. A foreign-root tree push wipes the per-nexus session state before any reconcile can leak one nexus's sets into another's sidecar.

Warmth is session-only and per-tab (`previewWarm.ts` + the shared `usePreviewWarm` hook): serialized editor state (undo included) plus the body's scroll, restored on switch-back with the fetch skipped entirely — the restored doc mounts synchronously. Captures are liveness-gated so a closed tab's trailing unmount capture can never resurrect its entry.

### Routing In

- **Container views** (B-1): a `page-preview` Collection's title clicks open the preview; ⌘-click is always the explicit full-page bypass to a new tab.
- **Sidebar rows** (B-2): the same owner-resolution branch, resolved by tree position.
- **Connections** (B-6): the nexus-wide `connectionsOpenInPreview` Personalization key routes wiki-link clicks to the preview. It's per-nexus, so it has no place in the SettingsPane configuration leaf (a collection-config surface) — no UI control yet; its home is Nathan's call. ⌘-click always takes the other route (the one modifier branch in the CM6 handler); from inside a preview it's additive — a new app tab opens behind, the preview stays.
- **⌘N while a preview is open** promotes the active tab to a new app tab and closes it (the window when it was the last) — routed through the native menu's new-tab message, since a renderer keydown can't beat a native accelerator.
- **Hover** (B-7): resting on a resolved connection past the intent delay blooms the hover card — a backdrop-free pane anchored to the link, dismissed by grace-timed pointer-leave or Escape. The card's page content is post-plan; the trigger + chassis are live.

### The NavWindow Flavor

The NavWindow is tab 1 of its own flavor: a perma-pinned, icon-only, non-orderable map tab whose content IS the window's whole body (search + rail + gallery). "Open in Preview" from its rows adds page tabs beside it when the window's routing override is on (persisted in the previews sidecar, default on; it has no UI control yet — its placement is Nathan's call); off routes to the floating window. An active page tab swaps the body for the editable embed and slides the rail closed (fading with the slide); the map tab is the return, refocusing the search. The strip lives in the content column beside the full-height rail — tabs start right of the sidebar exactly like the app's tab bar, and the row exists only past one tab, its height nudging the search down on the standard ease. A page tab whose own icon is the map glyph renders its type icon instead, so nothing masquerades as the pinned tab. The window paints the floating preview's tint, and opening it over a live page preview morphs the window (a FLIP from the preview's rect via `WindowMorph.ts`; the outgoing preview hides instantly on the 'morph' exit) — one window changing shape, never a dismiss + fresh open. The window's tab set is durable multi-session, restored on every open.

### The Inspector

The right-hand pane is the shared `SidePane` shell — the same component as the NavWindow's favorites rail (one material, one inner geometry, one per-window persisted width, side-signed edge resize), mounted overlay-right and slid by the window's `--io`; the NavWindow hosts the same inspector on its page tabs only (it dies on the map return). Its body is the front-matter inspector, properties only — no title or banner rows. Two Swift-style group fields (contexts, then properties) sit in rounded quaternary fills below the toolbar strip, each row an icon-leading label with its value hugging the right edge; pickers anchor to that right-side value field. Properties are *assigned*: a row shows once its key exists in front-matter (or was revealed this session), assigned-but-empty is valid, "+ Add Property" (a bare footnote below the fields, borrowing the Group/Sort property menu) reveals one, and right-click offers Remove Property. Editing runs through the table views' own primitives (Cell, PropertyPicker, CalendarPicker, PropertyEditor) with the optimistic-patch write path. A bottom subfield holds the footnote location breadcrumb — the page's container chain plus the page itself.

### Pending

- The hover card's embedded page content (read-only PageEmbed) + its full dismiss mechanics.
- The engulf's landing when the promoted page's main-pane fetch outlasts the FLIP (the pane can show the prior view for a beat — usually masked by warmth).
- The nav flavor's last-tab close motion is clipped by the strip row's height collapse (cosmetic).
- Multi-preview (A-B testing two windows) — the geometry store and slice shapes are ready; the singleton rule is product, not architecture.
