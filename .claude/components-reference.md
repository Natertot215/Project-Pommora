# Components Reference

Catalogue of every verified SwiftUI component in [`Pommora/Pommora/Components/`](../Pommora/Pommora/Components/). Every entry is swiftinterface-cited per [`swift-uix-rules.md`](swift-uix-rules.md). Read this before adding any new SwiftUI surface — pull from a known-good example here rather than writing from memory.

## Source of truth

Three authoritative sources, in this order. Every component entry below must cite at least one.

### 1. swiftinterface (exact API surface)

macOS 26 SDK SwiftUI swiftinterface:

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
```

Cite every entry below by `<symbol>` and approximate line number from a `grep -n` against that file at the time of adding.

### 2. Apple Developer Documentation (narrative API docs)

Root: <https://developer.apple.com/documentation/swiftui/>

Use for usage examples, parameter explanations, and behavior descriptions that the swiftinterface alone doesn't convey. Per `swift-uix-rules.md`, prefer the Context7 MCP server over web fetches for live versions.

### 3. Apple Human Interface Guidelines (visual + interaction spec)

Use HIG for spacing, typography, color, control sizing, window chrome, accessibility, motion, and dark-mode behavior — anything that determines how a component should *look and feel* on macOS.

Root: <https://developer.apple.com/design/human-interface-guidelines>

**Every page under this root is available** — the table below is a curated starting set for the most common surfaces, not an exclusive list. When a task touches a topic not in the table (e.g. `windows`, `menus`, `popovers`, `inspectors`, `sidebars`, `tab-views`, `notifications`, `accessibility`), navigate from the root or guess the slug (HIG URLs are predictable: `/design/human-interface-guidelines/<topic>`) and fetch it the same way.

Curated starting pages:

| Topic | URL |
|---|---|
| Components (root index) | <https://developer.apple.com/design/human-interface-guidelines/components> |
| Layout | <https://developer.apple.com/design/human-interface-guidelines/layout> |
| Toolbars | <https://developer.apple.com/design/human-interface-guidelines/toolbars> |
| Materials | <https://developer.apple.com/design/human-interface-guidelines/materials> |
| Search fields | <https://developer.apple.com/design/human-interface-guidelines/search-fields> |
| Color | <https://developer.apple.com/design/human-interface-guidelines/color> |
| Dark Mode | <https://developer.apple.com/design/human-interface-guidelines/dark-mode> |
| Typography | <https://developer.apple.com/design/human-interface-guidelines/typography> |
| Motion | <https://developer.apple.com/design/human-interface-guidelines/motion> |

When a component category is added below, link the relevant HIG page(s) — from this table or from any other page under the root — in that category's section header.

## Categories

(populated as `Components/` files are added — see Tasks 8–12)
