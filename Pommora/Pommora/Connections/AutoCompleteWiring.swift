import Foundation
import MarkdownPM

/// Pure, view-free logic for the `[[` autocomplete wiring (E5-D).
///
/// The actual presentation (`AutoCompleteWindow` placement, caret anchoring)
/// and the live NSTextView insertion are runtime concerns verified by manual
/// run — see `PageEditorView`. The decision logic that drives them is hoisted
/// here so it's a single source of truth AND independently unit-testable
/// (`AutoCompleteWiringTests`).
enum AutoCompleteWiring {

    /// Whether the autocomplete popup should be shown for a given inline-selection
    /// state. **Trigger gate (Nathan-locked):** show ONLY when the caret is inside
    /// a `[[ ]]` wiki-link AND at least one character has been typed inside the
    /// pair (non-empty placeholder). An empty pair (`[[]]`), a dormant `{{ }}`
    /// chip-link, an image embed, or `nil` (caret left the token) all suppress
    /// the popup.
    static func shouldShowAutocomplete(for state: InlineSelectionState?) -> Bool {
        guard let state else { return false }
        switch state.kind {
        case .wikiLink:
            return !state.selection.placeholder.isEmpty
        case .chipLink, .imageEmbed:
            return false
        }
    }

    /// The storage fragment inserted when a candidate is chosen. Title-only
    /// (LD-28 — no id in the fragment); the engine re-resolves the title on the
    /// next render. Always a `[[Title]]` wiki-link — `[[` is the only
    /// connection syntax (PagesV2 decision #3); the dormant `.chipLink` and
    /// `.imageEmbed` kinds never reach autocomplete.
    static func fragment(kind: InlineSelectionKind, title: String) -> String {
        _ = kind
        return "[[\(title)]]"
    }


    /// Maps an index `EntityRef` to the presentation-only `AutoCompleteCandidate`,
    /// carrying id + title through and falling back to the kind's default glyph
    /// when the entity has no icon (reusing the canonical `ContextDisplayResolver`
    /// mapping so the popup matches every other entity surface).
    static func candidate(from ref: EntityRef) -> AutoCompleteCandidate {
        AutoCompleteCandidate(
            id: ref.id,
            icon: ref.icon ?? ContextDisplayResolver.defaultIcon(for: ref.kind),
            title: ref.title
        )
    }

    static func candidates(from refs: [EntityRef]) -> [AutoCompleteCandidate] {
        refs.map(candidate(from:))
    }
}
