import Foundation

/// Pure, view-independent helpers for turning the relation create-draft
/// inputs (target + home name/icon + reverse name) into a finished
/// `PropertyDefinition` ready for the source manager's paired `addProperty`.
///
/// Factored out of `EditPropertyPane` so the build-draft → addProperty save
/// path is unit-testable without rendering the SwiftUI view (see
/// `EditPropertyPaneRelationTests`).
///
/// **Contract** (mirrors the at-add convention `PageTypeManager.addProperty`
/// / `ItemTypeManager.addProperty` consume):
/// - `reverseName` carries the *reverse display name* the user typed.
///   `addProperty` reads it as the reverse property's name; the
///   `DualRelationCoordinator` then mints the reverse property and writes its
///   ID into `dualProperty.syncedPropertyID`.
/// - `dualProperty.syncedPropertyID` is left empty at add-time — a non-nil
///   `dualProperty` is the pairing SIGNAL; the coordinator fills the real
///   reverse-property ID post-creation.
/// - `dualProperty.syncedPropertyDefinedOnTypeID` carries the resolved target
///   Type ID (derived from `relationTarget` — never a Collection). The
///   coordinator re-derives this from the resolved target, so the value is
///   advisory but kept self-consistent here.
enum RelationDraftBuilder {

    /// Resolves the target Type ID from a `RelationTarget` for use as
    /// `dualProperty.syncedPropertyDefinedOnTypeID`. Container Types return
    /// their ULID; Agenda singletons return their reserved ID. Tier / legacy
    /// Collection targets return `nil` — they are not paired-relation targets
    /// in the create-draft flow.
    static func targetTypeID(for target: PropertyDefinition.RelationTarget) -> String? {
        switch target {
        case .pageType(let id), .itemType(let id):
            return id
        case .agendaTasks:
            return ReservedTypeID.agendaTasks
        case .agendaEvents:
            return ReservedTypeID.agendaEvents
        case .pageCollection, .itemCollection, .contextTier:
            return nil
        }
    }

    /// Builds a finished relation `PropertyDefinition` from the create-draft
    /// inputs. Trims `name` / `reverseName`; mints the property ID when
    /// `existingID` is empty. Returns `nil` if the target cannot back a paired
    /// relation (tier / legacy Collection) — the Save action gates on a
    /// concrete user target, so this is defensive.
    static func makeFinishedDraft(
        existingID: String,
        name: String,
        icon: String?,
        target: PropertyDefinition.RelationTarget,
        reverseName: String,
        reverseIcon: String? = nil
    ) -> PropertyDefinition? {
        guard let targetID = targetTypeID(for: target) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedReverse = reverseName.trimmingCharacters(in: .whitespaces)

        return PropertyDefinition(
            id: existingID.isEmpty ? ReservedPropertyID.mintUserPropertyID() : existingID,
            name: trimmedName,
            type: .relation,
            icon: icon,
            relationTarget: target,
            reverseName: trimmedReverse,
            reverseIcon: reverseIcon,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",
                syncedPropertyDefinedOnTypeID: targetID
            )
        )
    }
}
