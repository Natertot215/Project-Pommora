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
| Layout and organization | <https://developer.apple.com/design/human-interface-guidelines/layout-and-organization> |
| Sidebars | <https://developer.apple.com/design/human-interface-guidelines/sidebars> |
| Split views | <https://developer.apple.com/design/human-interface-guidelines/split-views> |
| Column views | <https://developer.apple.com/design/human-interface-guidelines/column-views> |
| Outline views | <https://developer.apple.com/design/human-interface-guidelines/outline-views> |
| Toolbars | <https://developer.apple.com/design/human-interface-guidelines/toolbars> |
| Materials | <https://developer.apple.com/design/human-interface-guidelines/materials> |
| Search fields | <https://developer.apple.com/design/human-interface-guidelines/search-fields> |
| Color | <https://developer.apple.com/design/human-interface-guidelines/color> |
| Dark Mode | <https://developer.apple.com/design/human-interface-guidelines/dark-mode> |
| Typography | <https://developer.apple.com/design/human-interface-guidelines/typography> |
| Motion | <https://developer.apple.com/design/human-interface-guidelines/motion> |

When a component category is added below, link the relevant HIG page(s) — from this table or from any other page under the root — in that category's section header.

## Categories

### Layout

HIG: <https://developer.apple.com/design/human-interface-guidelines/layout-and-organization>

| Component | swiftinterface line | Use this for |
|---|---|---|
| `VStack` | SwiftUICore 1128 | Vertical stack with optional alignment + spacing |
| `HStack` | SwiftUICore 5404 | Horizontal stack with optional alignment + spacing |
| `ZStack` | SwiftUICore 341 | Depth stack — overlays children with optional alignment |
| `Spacer` | SwiftUICore 3419 | Flexible empty space inside a stack |
| `Divider` | SwiftUI 8816 | Thin separator line, axis inferred from container |

Note: `VStack`, `HStack`, `ZStack`, and `Spacer` are declared in the `SwiftUICore` swiftinterface (`MacOSX.sdk/.../SwiftUICore.framework/.../arm64e-apple-macos.swiftinterface`); `Divider` is declared in the `SwiftUI` swiftinterface at the path documented above. Re-exported through `import SwiftUI`.

Example file: [`LayoutComponents.swift`](../Pommora/Pommora/Components/LayoutComponents.swift). Five `#Preview` blocks: VStack, HStack, ZStack, Spacer, Divider.

---

### Text

HIG: <https://developer.apple.com/design/human-interface-guidelines/typography>

| Component | swiftinterface line | Use this for |
|---|---|---|
| `Text` | SwiftUICore 18180 | Read-only string with `.font`, `.foregroundStyle`, etc. |
| `Label` | SwiftUI 23050 | Icon + title pairing — preferred over hand-rolled `HStack { Image; Text }`. See L-001. |
| `TextField` | SwiftUI 5193 | Single-line text input with binding |

Example file: [`TextComponents.swift`](../Pommora/Pommora/Components/TextComponents.swift).

---

### Controls

HIG: <https://developer.apple.com/design/human-interface-guidelines/components>

| Component | swiftinterface line | Use this for |
|---|---|---|
| `Button` | SwiftUI 21934 | Tap action with title or custom label. Styles: `.bordered`, `.borderedProminent`, `.plain`, `.link`. |
| `Toggle` | SwiftUI 4916 | Boolean binding control with optional label |

Example file: [`ControlComponents.swift`](../Pommora/Pommora/Components/ControlComponents.swift).

---

(further categories will be appended in Tasks 11–12)
