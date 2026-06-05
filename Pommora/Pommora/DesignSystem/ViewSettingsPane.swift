import SwiftUI

/// Dynamically-sized View Settings popover pane: a width-locked pane that grows
/// from `PUI.Pane.minHeight` to `PUI.Pane.maxHeight` as its scrolling middle
/// fills, then scrolls the middle while the header + footer stay pinned.
///
/// Replaces the old fixed `measuredPaneHeight()` floor, so short panes sit at
/// the minimum and long ones (e.g. Edit Properties with many rows) grow to fit
/// before they ever scroll — the popout "sizes to content".
///
/// Three slots:
///   - `header` — pinned at the top (PaneHeader, plus any icon/title field rows).
///   - `content` — the scrolling middle. Provide the *inner* content only; this
///     container owns the single `ScrollView`. Grows to its natural height,
///     caps at the available space, scrolls beyond.
///   - `footer` — pinned at the bottom (Delete/Duplicate, New property). Optional.
///
/// Sizing: `pane = clamp(headerH + contentH + footerH, min, max)`. The middle is
/// then given `pane − headerH − footerH`, so the footer pins to the bottom even
/// when content is short (the middle absorbs the slack) — matching Design.md's
/// "footers pin to the bottom; the scrollable middle absorbs spare space".
///
/// Heights come from `onGeometryChange` (the codebase's measurement idiom — see
/// `ContextPicker.SizedPanel`). Each slot is wrapped in a zero-spacing `VStack`
/// so multi-view slots measure as a single frame. The content's measured height
/// is its natural height (a `ScrollView` never constrains its content along the
/// scroll axis), so it's independent of the pane frame — no layout feedback loop.
struct ViewSettingsPane<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        let chrome = headerHeight + footerHeight
        let paneHeight = min(max(chrome + contentHeight, PUI.Pane.minHeight), PUI.Pane.maxHeight)
        let scrollHeight = max(0, paneHeight - chrome)

        VStack(spacing: 0) {
            VStack(spacing: 0) { header }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    headerHeight = newHeight.rounded(.up)
                }

            ScrollView {
                VStack(spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        contentHeight = newHeight.rounded(.up)
                    }
            }
            .frame(height: scrollHeight)
            // Only rubber-band when content actually overflows — no elastic
            // wobble while the pane sits at the floor.
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 0) { footer }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    footerHeight = newHeight.rounded(.up)
                }
        }
        // `.top` pins the top edge: all height delta lands at the bottom so the
        // popout grows/shrinks downward only (the popover hangs below its toolbar
        // button), never nudging the top. Heights are measured rounded-up so
        // sub-pixel re-layout (e.g. focusing a field) doesn't micro-resize the
        // popover. The resize itself is the native NSPopover's (no SwiftUI anim).
        .frame(width: PUI.Pane.width, height: paneHeight, alignment: .top)
    }
}
