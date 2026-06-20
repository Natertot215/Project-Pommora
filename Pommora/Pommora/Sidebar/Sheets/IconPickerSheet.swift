//
//  IconPickerSheet.swift
//  Pommora
//
//  Hosts Pommora's native `IconPicker` and dispatches the chosen icon to the
//  right manager via the SidebarSheet.IconTarget switch. (Formerly wrapped the
//  third-party xnth97/SymbolPicker — replaced 2026-05-30 by the in-house picker,
//  which is compact + Liquid-Glass and exposes a nullable binding for clear.)
//
//  `IconPicker` auto-dismisses on pick / Remove Icon, so this wrapper provides no
//  Cancel/Save buttons of its own; the `.onChange` below persists the pick.
//

import SwiftUI

struct IconPickerSheet: View {
    let target: SidebarSheet.IconTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var pageContentManager

    /// Nullable binding so the picker exposes its built-in delete-icon button on
    /// macOS — a `nil` value clears the icon back to the entity's default.
    @State private var icon: String? = nil
    @State private var didInitialize = false

    var body: some View {
        IconPicker(symbol: $icon)
            .presentationBackground(.clear)
            .onAppear {
                guard !didInitialize else { return }
                didInitialize = true
                icon = currentIcon
            }
            .onChange(of: icon, initial: false) { oldValue, newValue in
                // Skip the initial-load assignment; only save once the user picks.
                guard didInitialize, oldValue != newValue else { return }
                let chosen = newValue
                Task {
                    await save(newIcon: chosen)
                }
            }
    }

    private var currentIcon: String? {
        switch target {
        case .area(let s): return s.icon
        case .topic(let t): return t.icon
        case .project(let p): return p.icon
        case .pageType(let t): return t.icon
        case .pageCollection(let c): return c.icon
        case .pageSet(let s): return s.icon
        case .page(let p, _, _, _): return p.frontmatter.icon
        case .savedView(let viewID, let containerID):
            return resolveSavedView(viewID: viewID, in: containerID)?.icon
        }
    }

    /// Resolves a SavedView live off the manager by container + view ID via
    /// `PageTypeManager.views(in:)` — the single source for the dual-container
    /// (PageType + PageCollection) view lookup.
    private func resolveSavedView(viewID: String, in containerID: String) -> SavedView? {
        vaultManager.views(in: containerID).first(where: { $0.id == viewID })
    }

    /// Runs a manager update, swallowing the thrown error: each manager sets its
    /// own `pendingError` on failure and SidebarToast surfaces it, so the catch
    /// here has nothing left to do.
    private func attempt(_ work: () async throws -> Void) async {
        do { try await work() } catch {}
    }

    private func save(newIcon: String?) async {
        switch target {
        case .area(let s):
            await attempt { try await areaManager.updateIcon(s, to: newIcon) }
        case .topic(let t):
            await attempt { try await topicManager.updateIcon(t, to: newIcon) }
        case .project(let p):
            await attempt { try await projectManager.updateIcon(p, to: newIcon) }
        case .pageType(let t):
            await attempt { try await vaultManager.updatePageTypeIcon(t, to: newIcon) }
        case .pageCollection(let c):
            await attempt { try await vaultManager.updatePageCollectionIcon(c, to: newIcon) }
        case .pageSet(let s):
            await attempt { try await pageSetManager.updatePageSetIcon(s, to: newIcon) }
        case .page(let p, let vault, let collection, let set):
            await attempt {
                try await pageContentManager.updatePageIcon(
                    p, to: newIcon, vault: vault, collection: collection, set: set)
            }
        case .savedView(let viewID, let containerID):
            await attempt {
                try await vaultManager.updateView(viewID, in: containerID) { $0.icon = newIcon }
            }
        }
    }
}
