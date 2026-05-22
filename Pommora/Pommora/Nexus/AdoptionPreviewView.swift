//
//  AdoptionPreviewView.swift
//  Pommora
//
//  Sheet shown after the user picks a non-empty folder. Lists what will
//  be created (Vaults + Collections + Pages/Items inferred), then takes
//  Adopt / Skip. The caller (`NexusManager` via `ContentView`) routes the
//  decision back into the `openPicked` continuation.
//

import SwiftUI

struct AdoptionPreviewView: View {
    let plan: AdoptionPlan
    let onResolve: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryRow
                    vaultsSection
                    collectionsSection
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
                count: plan.vaults.count, label: "Vault", systemImage: "folder.fill"
            )
            summaryStat(
                count: plan.collections.count, label: "Collection",
                systemImage: "folder.badge.plus"
            )
            summaryStat(
                count: plan.pagesPreviewCount, label: "Page", systemImage: "doc.text"
            )
            summaryStat(
                count: plan.itemsPreviewCount, label: "Item",
                systemImage: "doc.badge.gearshape"
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
                "Top-level folders → Vaults",
                detail: "A _vault.json sidecar will be written into each."
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
                "Sub-folders → Collections",
                detail: "A _collection.json sidecar will be written into each."
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
    private var skippedSection: some View {
        if !plan.skippedTopLevel.isEmpty {
            sectionHeader(
                "Skipped",
                detail: "These folders are never adopted (Agenda, hidden, or build cruft)."
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
