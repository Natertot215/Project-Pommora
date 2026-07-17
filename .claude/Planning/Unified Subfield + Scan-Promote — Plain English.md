# Unified Subfield + Scan-Promote — In Plain English

A companion to the Decision Log (the *what*) and the Implementation Plan (the *how*). This is the same story with the jargon stripped out.

## The one-sentence version

Right now Pommora has "floating" versions of things (the little preview window, the pop-up nav window) that look and behave differently from their "full-size" versions in the main area. This work makes them feel like the same thing at two sizes — mainly by giving the floating preview the same **footer bar** that full pages have, giving the new-tab search screen a **List/Gallery switch** in that footer, and making the "pop this out to full size" button mean the same thing everywhere.

## What a "Subfield" is

The **Subfield** is the thin bar along the bottom of a page in the main area. On a normal page it shows two things: on the left, a **breadcrumb** of where the page lives (which folder it's in), and on the right, a live **word / character / line count** that updates as you type. There's a little chevron you can click to hide or show it. That's it — a quiet status bar at the bottom.

## The four things we're building

**1. The floating preview gets a real footer.** Today, when you pop open a page in the little floating preview window, its location is crammed into the bottom of the *inspector* (the properties panel on the right). We're removing that and instead giving the preview the exact same bottom bar a full page has — breadcrumb on the left, live word/character/line count on the right, its own hide/show chevron. So a preview reads like a miniature full page instead of a stripped-down cousin.

**2. The new-tab screen gets a List/Gallery switch.** When you open a new tab (or close your last one), you land on the search-and-recents screen ("NavView"). Today it only shows recents as a grid of cards. We're adding a **List** view too, and — this is the tidy part — the switch to flip between List and Gallery lives *in that same footer bar*. The footer just shows different things depending on what you're looking at: a word count on a page, a List/Gallery switch on the new-tab screen. It's one bar that adapts, not a bunch of separate bars.

**3. List rows stop looking cramped.** In list view, the little "pinned" icons sit in a too-tight gutter and feel squished. We give list rows the same comfortable spacing that real table/list views use, so the pins have room to breathe. This applies to both the new-tab list and the floating nav window's list. (The gallery view and the search box are untouched.)

**4. "Pop out to full size" works from the nav window too (later).** The floating nav window and the floating preview already share the same toolbar. Its top-left "scan" button means "open this full-size." Today it only works on a page. We extend it so that from the nav window, it opens the full new-tab screen — carrying your current List/Gallery choice along. This one is **deferred** — a nice-to-have we'll build after the core is proven.

## The clever part (why this isn't as big as it sounds)

Two things collapsed a lot of the work:

- **The new-tab screen isn't a separate creature.** It lives in the main area, same as pages do. So it doesn't need its own special footer — it just *reuses* the main area's footer, which already knows how to show different content in different situations. Adding the List/Gallery switch is basically adding one new entry to a list the footer already reads from.

- **The "live word count in the preview" stays cheap by keeping to itself.** The main area already has one shared "what's being typed right now" slot that feeds the word count, the tab-memory, and the thumbnail systems — and that slot has exactly one owner: whatever page is focused in the main area. The preview does NOT reach into that slot (if it did, the moment you typed in a preview, the main page's live count would snap back to its last-*saved* number — a real bug we caught in review). Instead the preview keeps its own private little count for its own page, computed right there in the preview window. Nothing shared, nothing to rewire, and the two counts never step on each other. (Pommora's "most recent edit wins" rule still covers the odd case of the same page open in both places — the last save is the one that sticks, by design.)

## How the build goes, in order

We build it in phases, and we stop and check (and screenshot) after each one:

- **Phase A — the preview footer.** Give the footer an optional "describe *this* page instead of the main one" mode, wire the preview's editor to feed its word count, add the preview's own hide/show chevron, mount the footer at the bottom of the preview window, and delete the old crammed-in location line. *(This is the biggest phase.)*
- **Phase B — the new-tab switch.** Add the List/Gallery switch to the footer's menu of possible items, make the new-tab screen show the footer, build its List view, and store the choice properly so it survives restarts (and so flipping it actually redraws the screen). The floating nav window and the new-tab screen each remember their *own* choice — flipping one doesn't flip the other.
- **Phase C — the spacing fix.** Widen the list-row spacing so pins aren't squished. This one is small and independent — it can ship first if we want a quick win.
- **Phase D — the pop-out button (deferred).** Wire the nav window's scan button to open the full new-tab screen. Built last, on its own.

Nothing here touches how files are saved, how data syncs, or the core storage model — it's all about how these surfaces *look and behave*, reusing pieces that already exist rather than inventing new ones.

## What we deliberately decided NOT to do

- **We're not merging the floating nav window and the new-tab screen into one component.** They share pieces (the card grid, the list, now the footer switch) but stay separate surfaces on purpose — merging them would fight their genuinely different framing (a floating glass panel vs. a full-screen view with a banner).
- **We're not adding a guard to stop the same page being open in a preview and the main area at once.** It's allowed, and if you edit in both, the most-recent edit wins — which is Pommora's philosophy anyway, so it's working as intended, not a bug.
- **We're not touching the gallery view or the search box** — only the list rows get the new spacing.
