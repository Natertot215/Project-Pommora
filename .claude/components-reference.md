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

### 2. Apple Developer Documentation (narrative + canonical code examples)

Root: <https://developer.apple.com/documentation/swiftui/>

Each component's doc page (e.g. <https://developer.apple.com/documentation/swiftui/text>, <https://developer.apple.com/documentation/swiftui/navigationsplitview>) contains **canonical code examples** maintained by Apple. When writing or updating an entry in `Pommora/Pommora/Components/`, the example bodies should be derived from the Apple-documented code on these pages — not invented from memory or pattern-matched from blogs.

URL pattern is predictable: `https://developer.apple.com/documentation/swiftui/<lowercase-component-name>` (e.g. `vstack`, `navigationstack`, `tabview`).

Per `swift-uix-rules.md`, prefer the Context7 MCP server over web fetches for live versions.

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
| Menus and actions | <https://developer.apple.com/design/human-interface-guidelines/menus-and-actions> |
| Presentation | <https://developer.apple.com/design/human-interface-guidelines/presentation> |
| Selection and input | <https://developer.apple.com/design/human-interface-guidelines/selection-and-input> |
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

| Component | swiftinterface line | Apple Docs (canonical code) | Use this for |
|---|---|---|---|
| `VStack` | SwiftUICore 1128 | <https://developer.apple.com/documentation/swiftui/vstack> | Vertical stack with optional alignment + spacing |
| `HStack` | SwiftUICore 5404 | <https://developer.apple.com/documentation/swiftui/hstack> | Horizontal stack with optional alignment + spacing |
| `ZStack` | SwiftUICore 341 | <https://developer.apple.com/documentation/swiftui/zstack> | Depth stack — overlays children with optional alignment |
| `Spacer` | SwiftUICore 3419 | <https://developer.apple.com/documentation/swiftui/spacer> | Flexible empty space inside a stack |
| `Divider` | SwiftUI 8816 | <https://developer.apple.com/documentation/swiftui/divider> | Thin separator line, axis inferred from container |

Note: `VStack`, `HStack`, `ZStack`, and `Spacer` are declared in the `SwiftUICore` swiftinterface (`MacOSX.sdk/.../SwiftUICore.framework/.../arm64e-apple-macos.swiftinterface`); `Divider` is declared in the `SwiftUI` swiftinterface at the path documented above. Re-exported through `import SwiftUI`.

Example file: [`LayoutComponents.swift`](../Pommora/Pommora/Components/LayoutComponents.swift). Five `#Preview` blocks: VStack, HStack, ZStack, Spacer, Divider.

---

### Text

HIG: <https://developer.apple.com/design/human-interface-guidelines/typography>

| Component | swiftinterface line | Apple Docs (canonical code) | Use this for |
|---|---|---|---|
| `Text` | SwiftUICore 18180 | <https://developer.apple.com/documentation/swiftui/text> | Read-only string with `.font`, `.foregroundStyle`, etc. |
| `Label` | SwiftUI 23050 | <https://developer.apple.com/documentation/swiftui/label> | Icon + title pairing — preferred over hand-rolled `HStack { Image; Text }`. See L-001. |
| `TextField` | SwiftUI 5193 | <https://developer.apple.com/documentation/swiftui/textfield> | Single-line text input with binding |

Example file: [`TextComponents.swift`](../Pommora/Pommora/Components/TextComponents.swift).

---

### Controls

HIG: <https://developer.apple.com/design/human-interface-guidelines/components>

| Component | swiftinterface line | Apple Docs (canonical code) | Use this for |
|---|---|---|---|
| `Button` | SwiftUI 21934 | <https://developer.apple.com/documentation/swiftui/button> | Tap action with title or custom label. Styles: `.bordered`, `.borderedProminent`, `.plain`, `.link`. |
| `Toggle` | SwiftUI 4916 | <https://developer.apple.com/documentation/swiftui/toggle> | Boolean binding control with optional label |

Example file: [`ControlComponents.swift`](../Pommora/Pommora/Components/ControlComponents.swift).

---

### Lists

HIG:
- <https://developer.apple.com/design/human-interface-guidelines/outline-views>
- <https://developer.apple.com/design/human-interface-guidelines/components>

| Component | swiftinterface line | Apple Docs (canonical code) | Use this for |
|---|---|---|---|
| `List` | SwiftUI:6456 | <https://developer.apple.com/documentation/swiftui/list> | Vertical scrolling collection with optional `selection:` binding |
| `ForEach` | SwiftUICore:16946 | <https://developer.apple.com/documentation/swiftui/foreach> | Iteration inside `List` / `Form` / stacks; requires `Identifiable` or `id:` keypath |
| `Section` | SwiftUI:11007 | <https://developer.apple.com/documentation/swiftui/section> | Group rows under a header (and optional footer) |
| `Table` | SwiftUI:1119 | <https://developer.apple.com/documentation/swiftui/table> | Multi-column data display with sortable `KeyPath` columns |

Example file: [`ListComponents.swift`](../Pommora/Pommora/Components/ListComponents.swift).

---

### Navigation

HIG:
- <https://developer.apple.com/design/human-interface-guidelines/sidebars>
- <https://developer.apple.com/design/human-interface-guidelines/split-views>
- <https://developer.apple.com/design/human-interface-guidelines/column-views>

| Component | swiftinterface line | Apple Docs (canonical code) | Use this for |
|---|---|---|---|
| `NavigationStack` | SwiftUI:14608 | <https://developer.apple.com/documentation/swiftui/navigationstack> | Push-based navigation with `navigationDestination(for:)` |
| `NavigationSplitView` | SwiftUI:20410 | <https://developer.apple.com/documentation/swiftui/navigationsplitview> | Sidebar / content / detail. **Always pair with `.navigationSplitViewStyle(.prominentDetail)`** — see L-003. |
| `NavigationLink` | SwiftUI:11185 | <https://developer.apple.com/documentation/swiftui/navigationlink> | Value-based push (preferred) or label-based push |
| `TabView` | SwiftUI:2483 | <https://developer.apple.com/documentation/swiftui/tabview> | Top-level switching between independent panes |

Example file: [`NavigationComponents.swift`](../Pommora/Pommora/Components/NavigationComponents.swift).
