import SwiftUI

/// A lightweight, index-decoupled candidate for the autocomplete popup. Each
/// value is the icon + title the row renders. The editor maps the index's
/// `EntityRef` → `AutoCompleteCandidate`; this keeps the view a pure presentation
/// surface with no dependency on the index or any resolver.
struct AutoCompleteCandidate: Identifiable, Hashable {
    let id: String
    let icon: String  // SF Symbol name
    let title: String
}

/// **The candidate popup for `[[` page autocomplete.** As the user types
/// inside the brackets, this lists matching entities so they can pick one.
/// A PURE presentation component over a candidate list + callbacks — no index, no
/// resolver, no editor coupling.
///
/// **Surface (Nathan, 2026-06-06):** real macOS 26 Liquid Glass via
/// `.glassEffect(in: .rect(cornerRadius: 12))` — Apple drives the fill + chrome,
/// so there is no manual `.regularMaterial` + hairline border (that read as a flat
/// panel, not glass). Matches the app's other glass surfaces (ContentView,
/// NavDropdown, BackForwardButtons).
///
/// **Rows:** each candidate = the entity icon + title in body font, in an `HStack`
/// with tight inline padding (chip density, mirroring the Chips primitives).
///
/// **Match highlight:** matching is PREFIX (starts-with, case-insensitive), so the
/// matched span is always the LEADING `query.count` characters of the title.
/// `highlightSplit` returns that split positionally — the matched prefix renders in
/// label-primary (`.primary`), the remainder in label-secondary (`.secondary`).
///
/// **Selection + keys:** one row is highlighted with a subtle `.quaternary` fill.
/// Click → `onSelect`. The window is `.focusable()` so once the editor gives it
/// focus: ↑/↓ move the (clamped) selection, Enter → `onSelect(selected)`, Esc →
/// `onCancel()`. Selection resets when the candidate list changes.
///
/// **Sizing:** height grows with the candidate count, capped at 4 visible rows;
/// beyond 4 a `ScrollView` scrolls the full list and keeps the selected row visible
/// via `ScrollViewReader`. Width fits content within a sensible min/max.
///
/// An empty candidate list renders nothing — the parent simply doesn't present an
/// empty glass box.
///
/// The visual layout is verified via the Component-Library showcase (`Cmd+Shift+D`
/// → Chips → "Auto-Complete Window"); only `highlightSplit` is unit-tested.
struct AutoCompleteWindow: View {
    let candidates: [AutoCompleteCandidate]
    /// The in-bracket query — its length is the prefix-highlight span per row.
    let query: String
    let onSelect: (AutoCompleteCandidate) -> Void
    let onCancel: () -> Void

    /// Index of the highlighted candidate. Reset to 0 whenever the candidate list
    /// changes (a new query produces a new list, so the prior index is stale).
    @State private var selectedIndex: Int = 0

    /// Max rows shown before the list scrolls.
    private static let visibleRowCap = 4
    /// Fixed per-row height — drives both the cap math and `ScrollViewReader`.
    private static let rowHeight: CGFloat = 28
    private static let cornerRadius: CGFloat = PUI.Radius.large

    var body: some View {
        if candidates.isEmpty {
            EmptyView()
        } else {
            list
                .frame(minWidth: 160, maxWidth: 320)
                .clipShape(.rect(cornerRadius: Self.cornerRadius))
                // Real macOS 26 Liquid Glass: Apple drives the fill + chrome — no
                // manual `.regularMaterial` + hairline border (that read as a flat
                // panel, not glass). Matches the app's other glass surfaces
                // (ContentView, NavDropdown, BackForwardButtons). A single panel is
                // one glass surface, so no GlassEffectContainer is needed.
                .glassEffect(in: .rect(cornerRadius: Self.cornerRadius))
                .focusable()
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.return) {
                    commitSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                // A fresh query yields a fresh list; the prior selection is stale.
                .onChange(of: candidates) { _, _ in selectedIndex = 0 }
        }
    }

    @ViewBuilder
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, candidate in
                        AutoCompleteRow(
                            candidate: candidate,
                            queryLength: query.count,
                            isSelected: offset == selectedIndex,
                            height: Self.rowHeight
                        )
                        .id(offset)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(candidate) }
                    }
                }
            }
            .frame(height: contentHeight)
            .onChange(of: selectedIndex) { _, index in
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    /// Height = min(candidate count, cap) rows. ≤4 candidates → exact fit (no
    /// scroll); >4 → capped at 4 rows and the `ScrollView` scrolls the rest.
    private var contentHeight: CGFloat {
        CGFloat(min(candidates.count, Self.visibleRowCap)) * Self.rowHeight
    }

    private func moveSelection(_ delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(0, min(candidates.count - 1, selectedIndex + delta))
    }

    private func commitSelection() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelect(candidates[selectedIndex])
    }

    // MARK: - Pure highlight helper (unit-tested)

    /// Splits `title` into the matched leading prefix + the remaining tail, PURELY
    /// by position: prefix-matching already guarantees the leading `queryLength`
    /// characters matched, so the split is `queryLength` clamped to `title.count`.
    /// Returns `(matched, rest)` as substrings of `title`.
    static func highlightSplit(title: String, queryLength: Int) -> (matched: Substring, rest: Substring) {
        let clamped = max(0, min(queryLength, title.count))
        let cut = title.index(title.startIndex, offsetBy: clamped)
        return (title[..<cut], title[cut...])
    }
}

/// One candidate row: icon + the prefix-highlighted title in body font, with a
/// subtle `.quaternary` fill when selected. Tight inline padding mirrors the Chips primitives.
private struct AutoCompleteRow: View {
    let candidate: AutoCompleteCandidate
    let queryLength: Int
    let isSelected: Bool
    let height: CGFloat

    var body: some View {
        let split = AutoCompleteWindow.highlightSplit(title: candidate.title, queryLength: queryLength)
        HStack(spacing: PUI.Spacing.sm) {
            Image(systemName: candidate.icon)
                .foregroundStyle(.secondary)
            Text("\(Text(split.matched).foregroundStyle(.primary))\(Text(split.rest).foregroundStyle(.secondary))")
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.horizontal, PUI.Spacing.md)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PUI.Radius.card, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .padding(.horizontal, PUI.Spacing.xs)
    }
}
