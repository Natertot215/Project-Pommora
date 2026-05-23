//
//  AdoptionPreviewView.swift
//  Pommora
//
//  Sheet shown after the user picks a non-empty folder. Lists what will be
//  created — PageTypes + PageCollections (Pages-side) and ItemTypes +
//  ItemCollections (Items-side) — plus a count of any legacy-shaped folders
//  at the nexus root that adoption is intentionally not touching (Phase 10's
//  user-data migration owns that relocation).
//
//  UI vocabulary mirrors the per-side divergence locked in CLAUDE.md:
//  Pages-side defaults are "Vault" + "Collection"; Items-side defaults are
//  "Type" + "Set". Hardcoded here for v0.3.0; Phase 7's SettingsManager will
//  swap these for user-overridable values.
//

import SwiftUI

struct AdoptionPreviewView: View {
    let plan: AdoptionPlan
    let onResolve: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    // Default UI labels per CLAUDE.md "UI vocabulary diverges per side".
    // Phase 7's SettingsManager will route these through user-overridable
    // values; hardcoded here so adoption preview ships green standalone.
    private let vaultLabel = "Vault"
    private let collectionLabel = "Collection"
    private let typeLabel = "Type"
    private let setLabel = "Set"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryRow
                    vaultsSection
                    collectionsSection
                    itemTypesSection
                    itemCollectionsSection
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 16)
    }

    private var summaryRow: some View {
        HStack(spacing: 24) {
            summaryStat(
                count: plan.vaults.count, label: vaultLabel, systemImage: "folder.fill"
            )
            summaryStat(
                count: plan.collections.count, label: collectionLabel,
                systemImage: "folder.badge.plus"
            )
            summaryStat(
                count: plan.itemTypes.count, label: typeLabel,
                systemImage: "tablecells"
            )
            summaryStat(
                count: plan.itemCollections.count, label: setLabel,
                systemImage: "square.stack.3d.up"
            )
            Spacer()
        }
    }

    private func summaryStat(count: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
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
    private var vaultsSection: some View {
        if !plan.vaults.isEmpty {
            sectionHeader(
                "Pages/ → \(vaultLabel)s",
                detail:
                    "\(plan.pagesPreviewCount) page\(plan.pagesPreviewCount == 1 ? "" : "s") inferred. A _schema.json sidecar will be written into each."
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.vaults) { vault in
                    rowLabel(systemImage: "folder.fill", title: vault.title)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        if !plan.collections.isEmpty {
            sectionHeader(
                "Sub-folders → \(collectionLabel)s",
                detail: "A _schema.json sidecar will be written into each."
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.collections) { coll in
                    rowLabel(
                        systemImage: "folder",
                        title: coll.title,
                        subtitle: coll.vaultFolderURL.lastPathComponent
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var itemTypesSection: some View {
        if !plan.itemTypes.isEmpty {
            sectionHeader(
                "Items/ → \(typeLabel)s",
                detail:
                    "\(plan.itemsPreviewCount) item\(plan.itemsPreviewCount == 1 ? "" : "s") inferred. A _schema.json sidecar will be written into each."
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.itemTypes) { itemType in
                    rowLabel(systemImage: "tablecells", title: itemType.title)
                }
            }
        }
    }

    @ViewBuilder
    private var itemCollectionsSection: some View {
        if !plan.itemCollections.isEmpty {
            sectionHeader(
                "Sub-folders → \(setLabel)s",
                detail: "A _schema.json sidecar will be written into each."
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.itemCollections) { coll in
                    rowLabel(
                        systemImage: "square.stack.3d.up",
                        title: coll.title,
                        subtitle: coll.itemTypeFolderURL.lastPathComponent
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var skippedSection: some View {
        if !plan.skippedTopLevel.isEmpty {
            sectionHeader(
                "Skipped — \(plan.skippedTopLevel.count) legacy folder\(plan.skippedTopLevel.count == 1 ? "" : "s")",
                detail:
                    "Folders at the nexus root aren't adopted directly. Phase 10's migration will move them into Pages/."
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.skippedTopLevel, id: \.self) { url in
                    rowLabel(
                        systemImage: "folder.badge.minus",
                        title: url.lastPathComponent,
                        muted: true
                    )
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rowLabel(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        muted: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(muted ? .tertiary : .secondary)
                .frame(width: 16)
            Text(title)
                .font(.callout)
                .foregroundStyle(muted ? .secondary : .primary)
            if let subtitle {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
