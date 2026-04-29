# Lesson: Verify SwiftUI APIs against the source — never invent from memory

**Read this before:** introducing or modifying any SwiftUI modifier, initializer, type, or protocol conformance. Including ones that "obviously" exist.

## The mistake

Writing SwiftUI code based on what the API "probably" looks like, then having it fail to compile or — worse — compile but behave wrong because:

- The modifier doesn't exist on macOS 26 (or never existed at all)
- The signature has different parameter labels than I remembered
- A required associated type, generic constraint, or platform availability annotation is missing
- The modifier exists but does something subtly different than I assumed

## Why it's wrong

Apple's web docs are JS-rendered and frequently fail to fetch. My training data has gaps and contradictions across SwiftUI versions. Memory is unreliable for API surface. When I guess and ship, the failure mode is silent — code "looks right" but isn't.

## The rule

Before introducing or changing any SwiftUI surface, **read an authoritative source and cite it**. Source-of-truth hierarchy (most authoritative first):

1. **The SwiftUI `.swiftinterface`** in the macOS 26 SDK:
   ```
   /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
   ```
   Use `grep -n` for exact signatures, generics, defaults, and `@available` annotations. Example:
   ```bash
   grep -n "func draggable" /Applications/Xcode.app/.../arm64e-apple-macos.swiftinterface
   ```
   When citing, include the file and the line number.

2. **Apple SwiftUI documentation** — <https://developer.apple.com/documentation/swiftui>. Narrative explanation. Often unreachable; fall back to (1).

3. **Apple Human Interface Guidelines** — <https://developer.apple.com/design/human-interface-guidelines>. For visual correctness (sidebar widths, list row sizes, materials).

4. **Shipped macOS apps** (Finder, Mail, Notes, Photos, Settings, Xcode). When the HIG doesn't pixel-spec something, the canonical apps *are* the reference.

## Verification protocol

1. Name the modifier/type you're about to use.
2. Grep the `.swiftinterface` (or open Apple docs) and confirm:
   - It exists.
   - Its signature matches what you intend to write.
   - It's available on macOS 26 (no `@available(macOS, deprecated:)` past our floor).
3. If the source is unreachable, **say so to Nathan**. Don't guess.
4. In the code change description, cite where you verified — file + line, or URL.

"I think this is how it works" is not acceptable.

## Pairs with

- [ui-dimensions-and-semantic-primitives.md](ui-dimensions-and-semantic-primitives.md) — once you've verified the API exists, that lesson tells you which primitive to actually reach for.

## Incidents

- **2026-04-28 — Drag-reorder rewrite spiral (4 rejected iterations).** Four successive drag-reorder implementations were rejected because the architectural constraint was never surfaced: `.listStyle(.sidebar)` delegates to `NSOutlineView`, which forces the legacy blue insertion-bar drag regardless of what SwiftUI drag modifiers you apply. The macOS 26 container-drag API (`dragContainer`, `draggable(_:id:containerNamespace:)`) only works correctly under `.listStyle(.inset)` or `.listStyle(.plain)`. Because this was never verified against the swiftinterface and HIG before starting, four iterations were wasted trying to make the new API work in a list style that fights it. Lesson: before any drag/drop rewrite, grep the swiftinterface for the relevant drag modifier signatures, check `@available` annotations, and confirm which list styles are compatible. Surface architectural constraints to Nathan before writing code.
