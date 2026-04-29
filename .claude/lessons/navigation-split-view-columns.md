# Lesson: NavigationSplitView column coupling — use .prominentDetail for independent columns

**Read this before:** any change to `NavigationSplitView` layout, column widths, or split-view style.

## The mistake

Leaving `NavigationSplitView` at its default `.balanced` style when the design intent is independent column resizing. The default distributes available width proportionally — dragging the sidebar divider causes the middle column to shrink or grow to compensate.

## Why it's wrong

In a three-column layout (sidebar / content / detail), the user expects:
- Dragging the sidebar divider → only the editor (detail) absorbs the change
- Dragging the content divider → only the editor absorbs the change
- Middle column width is not coupled to sidebar width

The `.balanced` style violates this by sharing width changes across all columns. Nathan's framing: "adjusting the sidebar should not impact the other bars."

## The rule

Add `.navigationSplitViewStyle(.prominentDetail)` to the `NavigationSplitView` when sidebar and content columns must resize independently. The detail column (editor) becomes the flexible absorber.

```swift
NavigationSplitView { ... } content: { ... } detail: { ... }
    .navigationSplitViewStyle(.prominentDetail)
```

Verify: `grep -n "prominentDetail" …arm64e-apple-macos.swiftinterface` — it's `ProminentDetailNavigationSplitViewStyle`, available macOS 13+.

## Incidents

- **2026-04-28** — Initial occurrence. Walking skeleton shipped with default `.balanced` style. Nathan reported "adjusting the sidebar adjusts the other [column]." Fixed by adding `.navigationSplitViewStyle(.prominentDetail)` to `ContentView.swift`.
