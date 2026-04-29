# Feedback — direct corrections from Nathan

This file captures behavior rules Nathan has explicitly corrected during sessions. Every entry is a real incident. Each rule applies to all future Pommora work.

---

## Don't claim something is fixed without running the app

**Rule:** Never report a visual or behavioral fix as done unless you have actually run the app and verified it. Build success is not the same as correct behavior.

**Why:** Multiple drag-reorder iterations were described as "working" or "better" in the response before Nathan ran them and found they were wrong. This happened 4 times in a row. It wasted the session.

**How to apply:** After any UI/interaction change, explicitly state whether you ran the app or not. If you cannot run it (no Xcode access in this environment), say that explicitly and describe exactly what Nathan should verify — do not imply it's done.

---

## Four rejections = architectural problem, not an implementation problem

**Rule:** If the same category of fix is rejected more than twice, stop and surface the architectural constraint before attempting another implementation.

**Why:** The drag-reorder work was rejected 4 times. The root cause was architectural (`.listStyle(.sidebar)` + NSOutlineView = legacy blue-bar drag, incompatible with the macOS 26 container-drag API). That constraint was never surfaced. Instead, each iteration was a new variation on the same wrong approach.

**How to apply:** After the second rejection of the same feature, say: "This is failing repeatedly. Let me explain the architectural constraint I think I'm hitting, and ask how you want to resolve it before I write more code."

---

## "Swift ONLY items" means no AppKit wraps

**Rule:** Nathan has explicitly said "swift ONLY items" — `NSViewRepresentable` wrapping `NSOutlineView` or `NSTextView` is off the table for v1.0. Do not propose AppKit solutions.

**Why:** The final option for Finder-style drag in the sidebar was an `NSOutlineView` wrap. Nathan rejected this direction outright. He prefers a SwiftUI-only constraint even if it means deferring features.

**How to apply:** When SwiftUI cannot achieve what the user wants natively, surface that clearly ("This requires AppKit, which is out of scope") and suggest deferring — do not propose the AppKit path as a solution.

---

## DerivedData must be pinned before any behavioral debugging

**Rule:** Before debugging unexpected app behavior, confirm that `xcodebuild` and the running Xcode build share the same DerivedData hash. A mismatch means your changes are not in the running app.

**Why:** During the session, I had been building to `Pommora-fytgnsxnxwozlabwmanlcscyocuv` while the running app was from `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Nathan caught this: "is it possible the xcode vs is not in sync?" Multiple rounds of debugging were wasted because the wrong binary was running.

**How to apply:** At the start of any behavioral debugging session, run: `ls ~/Library/Developer/Xcode/DerivedData/ | grep Pommora` and confirm there is exactly one DerivedData entry and it matches what xcodebuild uses. Pin with `-derivedDataPath` if needed.

---

## Orphan files are first-class — treat them identically to folder files

**Rule:** Any code path that handles files must handle orphan files (`folder == nil`) with exactly the same logic as folder-resident files. No special caps, no skipped indexing, no second-class selection.

**Why:** The orphan overflow branch (`orphanRow` + `ScrollView` cap of 25) was a scrapped-feature artifact that survived. Search also silently excluded orphans. Nathan noted it was a scrapped feature that "should have been removed." These were caught only in a code review — they should have been caught before shipping.

**How to apply:** When writing or reviewing any file-related code, explicitly check: "Does this also handle `file.folder == nil`?" If there's a separate orphan path, justify it or delete it.

---

## Sidebar column resizing must not affect the middle column

**Rule:** In the three-column `NavigationSplitView`, the editor (detail) column is the flexible absorber. Resizing the sidebar must not change the middle column width, and vice versa.

**Why:** The default `.balanced` style couples column widths. Nathan flagged this: "adjusting the sidebar should not impact the other bars." Fix: `.navigationSplitViewStyle(.prominentDetail)`.

**How to apply:** Any `NavigationSplitView` in Pommora must use `.prominentDetail`. This is now in place in `ContentView.swift`.

---

## Push back on scope before starting, not after four iterations

**Rule:** If a requested feature has a fundamental constraint that makes it impossible (or very hard) in the current architecture, say so before writing any code — not after the fourth failed attempt.

**Why:** The Finder-style displacement drag was fundamentally incompatible with `.listStyle(.sidebar)`. This should have been diagnosed upfront (30 minutes of swiftinterface research) instead of discovered across 4 code iterations that consumed the entire session.

**How to apply:** Before any drag/drop, animation, or layout rewrite: spend time in the swiftinterface first. Identify the primitive. Confirm it works in the target list style. Only then write code.
