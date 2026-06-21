import Foundation

/// View-model for the Grouping pane. Owns the draft `GroupConfig`, the
/// grouping-enabled toggle, and the "last picked" memory so toggling off
/// and back on restores the previous property without asking the user to
/// re-select. Testable without SwiftUI rendering (J.5 pattern).
///
/// Discrete picks commit immediately — no debounce (inline-edit-commit
/// precedent: only free-text keystroke streams need coalescing).
@Observable
@MainActor
final class GroupingPaneModel {
    private(set) var config: GroupConfig
    var groupingEnabled: Bool
    private var remembered: PropertyGrouping?
    let onSave: (GroupConfig) -> Void

    init(config: GroupConfig, onSave: @escaping (GroupConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        if case .property(let g) = config {
            groupingEnabled = true
            remembered = g
        } else {
            groupingEnabled = false
            remembered = nil
        }
    }

    // MARK: - Derived state

    /// The active `PropertyGrouping`, or nil when not property-grouped.
    var grouping: PropertyGrouping? {
        if case .property(let g) = config { return g }
        return nil
    }

    // MARK: - Mutations

    /// Toggle grouping on or off.
    ///
    /// ON: if a property was previously remembered, restore it immediately
    /// (writes `.property` + saves). If nothing is remembered, flip
    /// `groupingEnabled` to true as a UI-only intermediate — `config` stays
    /// `.structural` and `onSave` is NOT called until a property is picked.
    ///
    /// OFF: revert to `.structural` and save; keep `remembered` so a
    /// subsequent ON can restore the property without re-selection.
    func setGroupingEnabled(_ on: Bool) {
        groupingEnabled = on
        if on {
            if let r = remembered {
                config = .property(r)
                onSave(config)
            }
            // else: UI-only intermediate — no save until selectProperty fires
        } else {
            config = .structural
            onSave(config)
        }
    }

    /// Pick a group-by property. Restores the remembered grouping when the id
    /// matches (preserving its order/mode/granularity); otherwise starts fresh.
    func selectProperty(_ id: String) {
        let g = (remembered?.propertyID == id) ? remembered! : PropertyGrouping(propertyID: id)
        remembered = g
        config = .property(g)
        onSave(config)
    }

    /// Mutate the active grouping (order mode, granularity, order, empty
    /// controls) and save immediately.
    func update(_ mutate: (inout PropertyGrouping) -> Void) {
        guard case .property(var g) = config else { return }
        mutate(&g)
        remembered = g
        config = .property(g)
        onSave(config)
    }
}
