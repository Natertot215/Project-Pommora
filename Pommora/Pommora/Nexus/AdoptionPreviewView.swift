//
//  AdoptionPreviewView.swift
//  Pommora
//
//  Sheet shown after the user picks a folder. Lists the on-disk migrations the
//  adopter will perform — fresh sidecar writes (shape #1), legacy-sidecar
//  in-place renames (shape #2), paradigmV2 wrapper unwraps (shape #3), and
//  already-flat no-ops (shape #4). Warnings surface in a collapsible
//  disclosure; post-apply per-folder failures flow through NexusManager's
//  `pendingError` alert (the apply pass runs after the sheet dismisses).
//
//  UI vocabulary defaults to the labels from SettingsLabels
//  ("Vault" / "Collection"). Adoption
//  runs before SettingsManager is constructed for a fresh Nexus, so we read
//  from `SettingsLabels.defaults()` directly — Phase 7's per-Nexus overrides
//  apply on subsequent launches once the nexus is open.
//

import SwiftUI

struct AdoptionPreviewView: View {
    let plan: AdoptionPlan
    /// Optional Phase C.5 migration plan — surfaces alongside adoption work
    /// so the user can preview both before committing. Nil when no
    /// migration is needed; the sheet still presents adoption-only.
    let migrationPlan: PropertyIDMigration.Plan?
    let onResolve: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Default UI labels — adoption happens before SettingsManager is built so
    /// we go through SettingsLabels' default seed (the seed values are the
    /// canonical per-side defaults; per-Nexus overrides land later).
    private let labels = SettingsLabels.defaults()

    init(
        plan: AdoptionPlan,
        migrationPlan: PropertyIDMigration.Plan? = nil,
        onResolve: @escaping (Bool) -> Void
    ) {
        self.plan = plan
        self.migrationPlan = migrationPlan
        self.onResolve = onResolve
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryRow
                    unwrapsSection
                    inPlaceRenamesSection
                    freshSidecarsSection
                    propertyMigrationSection
                    alreadyFlatSection
                    warningsSection
                    skippedSection
                }
                .padding(20)
            }
            .frame(minHeight: 240, idealHeight: 360, maxHeight: 460)

            Divider()

            footer
        }
        .frame(minWidth: 520, idealWidth: 560)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PUI.Spacing.xl) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: PUI.Spacing.xxs) {
                Text("Adopt Existing Folder Structure")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(plan.nexusRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, PUI.Spacing.xxl)
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            // Per-side migration counts (entity-oriented).
            HStack(spacing: PUI.Spacing.xxxl) {
                summaryStat(
                    count: pageTypeMigrationCount,
                    label: labels.pageType.singular,
                    systemImage: "folder.fill"
                )
                summaryStat(
                    count: agendaMigrationCount,
                    label: "Agenda",
                    systemImage: "calendar"
                )
                Spacer()
            }
            // Pre-flight totals (operation-oriented). Mirrors the post-apply
            // summary surfaced via NexusManager's `pendingError` for failures
            // — keeps expectations in front of the user before they commit.
            HStack(spacing: PUI.Spacing.xxl) {
                Text("\(totalMigrationCount) to migrate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if plan.alreadyFlat.count > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(plan.alreadyFlat.count) already adopted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if plan.warnings.count > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(plan.warnings.count) warning\(plan.warnings.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
        }
    }

    private func summaryStat(count: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: PUI.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(label + (count == 1 ? "" : "s"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var unwrapsSection: some View {
        if !plan.unwrapSteps.isEmpty {
            let totalMoves = plan.unwrapSteps.reduce(0) { $0 + $1.moves.count }
            sectionHeader(
                "Unwrap wrappers (\(totalMoves) folder\(totalMoves == 1 ? "" : "s"))",
                detail:
                    "Pre-existing wrapper folders (Pages/Agenda) will be dissolved — their children move to the nexus root."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(plan.unwrapSteps) { unwrap in
                    ForEach(unwrap.moves) { move in
                        unwrapMoveRow(move, wrapperName: unwrap.wrapperURL.lastPathComponent)
                    }
                }
            }
        }
    }

    private func unwrapMoveRow(_ move: PlannedUnwrap.ChildMove, wrapperName: String) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: iconForSidecar(move.typeSidecar))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: PUI.Spacing.sm) {
                    Text("\(wrapperName)/\(move.sourceURL.lastPathComponent)")
                        .font(.callout)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(move.destURL.lastPathComponent + "/")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(labelForSidecar(move.typeSidecar))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var inPlaceRenamesSection: some View {
        if !plan.inPlaceRenames.isEmpty {
            sectionHeader(
                "Rename legacy sidecars (\(plan.inPlaceRenames.count))",
                detail:
                    "Pre-ParadigmV2 sidecar files (_vault.json / _collection.json) will be renamed to the per-kind flat-layout names."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(plan.inPlaceRenames) { rename in
                    HStack(spacing: PUI.Spacing.md) {
                        Image(systemName: "doc.badge.gearshape")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rename.folderURL.lastPathComponent)
                                .font(.callout)
                            HStack(spacing: PUI.Spacing.xs) {
                                Text(rename.oldSidecar)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(rename.newSidecar)
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var freshSidecarsSection: some View {
        if !plan.freshSidecars.isEmpty {
            sectionHeader(
                "Write fresh sidecars (\(plan.freshSidecars.count))",
                detail:
                    "Folders without a recognized sidecar get a fresh per-kind sidecar based on their contents."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(plan.freshSidecars) { fresh in
                    HStack(spacing: PUI.Spacing.md) {
                        Image(systemName: iconForSidecar(fresh.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fresh.title)
                                .font(.callout)
                            Text(labelForSidecar(fresh.kind))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var propertyMigrationSection: some View {
        if let migrationPlan, migrationPlan.hasAnyMigration {
            sectionHeader(
                "Migrate property IDs (\(migrationPlan.totalTypes) \(migrationPlan.totalTypes == 1 ? "Type" : "Types"))",
                detail:
                    "Pre-v0.3.0 schemas use property name as identity. v0.3.0 introduces stable ULID property IDs — "
                    + "\(migrationPlan.totalPropertiesToMint) new property "
                    + "ID\(migrationPlan.totalPropertiesToMint == 1 ? "" : "s") will be minted; up to "
                    + "\(migrationPlan.totalMemberFileCandidates) member "
                    + "file\(migrationPlan.totalMemberFileCandidates == 1 ? "" : "s") may be rewritten "
                    + "to key properties by ID. Orphan property values preserved."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(Array(migrationPlan.pageTypeMigrations.enumerated()), id: \.offset) { _, m in
                    propertyMigrationRow(m)
                }
            }
        }
    }

    private func propertyMigrationRow(_ m: PropertyIDMigration.TypeMigration) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.typeTitle)
                    .font(.callout)
                HStack(spacing: PUI.Spacing.sm) {
                    Text("\(m.propertiesToMint) propert\(m.propertiesToMint == 1 ? "y" : "ies") to mint")
                    if m.memberFileCandidates > 0 {
                        Text("·").foregroundStyle(.tertiary)
                        Text(
                            "\(m.memberFileCandidates) member "
                                + "file\(m.memberFileCandidates == 1 ? "" : "s")"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var alreadyFlatSection: some View {
        if !plan.alreadyFlat.isEmpty {
            sectionHeader(
                "Already adopted (\(plan.alreadyFlat.count))",
                detail:
                    "Folders already in the flat layout — no migration needed; orphan-cleanup pass runs."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(plan.alreadyFlat) { flat in
                    HStack(spacing: PUI.Spacing.md) {
                        Image(systemName: iconForSidecar(flat.kind))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(flat.folderURL.lastPathComponent)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !plan.warnings.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
                    ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                        Text("• " + warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, PUI.Spacing.sm)
            } label: {
                Label(
                    "Warnings (\(plan.warnings.count))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var skippedSection: some View {
        if !plan.skippedTopLevel.isEmpty {
            sectionHeader(
                "Skipped — \(plan.skippedTopLevel.count) folder\(plan.skippedTopLevel.count == 1 ? "" : "s")",
                detail:
                    "Folders at the nexus root that don't look like Pommora data are left untouched."
            )
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                ForEach(plan.skippedTopLevel, id: \.self) { url in
                    HStack(spacing: PUI.Spacing.md) {
                        Image(systemName: "folder.badge.minus")
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xxs) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Skip — open empty") {
                onResolve(false)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Adopt") {
                onResolve(true)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(adoptDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Adopt is always enabled post-Relations-redesign (no lossy changes remain).
    private var adoptDisabled: Bool { false }

    // MARK: - Label helpers

    private var pageTypeMigrationCount: Int {
        let fresh = plan.freshSidecars.filter { $0.kind == .pageType }.count
        let renames = plan.inPlaceRenames.filter { $0.newSidecar == NexusPaths.pageTypeSidecarFilename }.count
        let unwraps = plan.unwrapSteps
            .filter { $0.wrapperKind == .pages }
            .reduce(0) { $0 + $1.moves.count }
        return fresh + renames + unwraps
    }

    private var agendaMigrationCount: Int {
        let fresh = plan.freshSidecars.filter { $0.kind == .taskConfig || $0.kind == .eventConfig }.count
        let unwraps = plan.unwrapSteps
            .filter { $0.wrapperKind == .agenda }
            .reduce(0) { $0 + $1.moves.count }
        return fresh + unwraps
    }

    /// Total folders that will be migrated (any shape that produces a write).
    /// Excludes already-flat folders (no-op) and skipped folders.
    private var totalMigrationCount: Int {
        let unwraps = plan.unwrapSteps.reduce(0) { $0 + $1.moves.count }
        return plan.freshSidecars.count + plan.inPlaceRenames.count + unwraps
    }

    private func iconForSidecar(_ kind: AdoptedSidecarKind) -> String {
        switch kind {
        case .pageType, .pageCollection, .pageSet: return "folder.fill"
        case .taskConfig: return "checkmark.circle"
        case .eventConfig: return "calendar"
        }
    }

    private func labelForSidecar(_ kind: AdoptedSidecarKind) -> String {
        switch kind {
        case .pageType: return labels.pageType.singular
        case .pageCollection: return labels.pageCollection.singular
        case .pageSet: return labels.pageSet.singular
        case .taskConfig: return labels.agendaTask.plural
        case .eventConfig: return labels.agendaEvent.plural
        }
    }
}
