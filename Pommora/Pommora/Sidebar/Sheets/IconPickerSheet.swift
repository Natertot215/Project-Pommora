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
        case .page(let p, _, _): return p.frontmatter.icon
        }
    }

    private func save(newIcon: String?) async {
        // pendingError is set by each manager on failure; SidebarToast surfaces it.
        switch target {
        case .area(let s):
            do { try await areaManager.updateIcon(s, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .topic(let t):
            do { try await topicManager.updateIcon(t, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .project(let p):
            do { try await projectManager.updateIcon(p, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .pageType(let t):
            do { try await vaultManager.updatePageTypeIcon(t, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .pageCollection(let c):
            do { try await vaultManager.updatePageCollectionIcon(c, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .page(let p, let vault, let collection):
            do { try await pageContentManager.updatePageIcon(p, to: newIcon, vault: vault, collection: collection) } catch
            { /* pendingError set by manager; toast surfaces */  }
        }
    }
}
