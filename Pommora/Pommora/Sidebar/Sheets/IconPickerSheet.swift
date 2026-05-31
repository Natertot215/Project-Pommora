//
//  IconPickerSheet.swift
//  Pommora
//
//  Wraps xnth97/SymbolPicker behind Pommora's IconPickerSheet per the locked
//  paradigm decision (.claude/Guidelines/Paradigm-Decisions.md #3). The wrapper
//  isolates the third-party library so swapping is a single-file rewrite, and
//  dispatches the chosen icon to the right manager via the SidebarSheet.IconTarget
//  switch.
//
//  SymbolPicker (1.6.2) renders its own chrome — search field, x-close button,
//  symbol grid, and on macOS a delete button when the binding is nullable and a
//  symbol is currently selected. It auto-dismisses on symbol pick, delete, or
//  close — so this wrapper does not provide Cancel/Save buttons of its own.
//

import SwiftUI
import SymbolPicker

struct IconPickerSheet: View {
    let target: SidebarSheet.IconTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    /// Nullable binding so the picker exposes its built-in delete-icon button on
    /// macOS — a `nil` value clears the icon back to the entity's default.
    @State private var icon: String? = nil
    @State private var didInitialize = false

    var body: some View {
        SymbolPicker(symbol: $icon)
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
        case .space(let s): return s.icon
        case .topic(let t): return t.icon
        case .project(let p): return p.icon
        case .pageType(let t): return t.icon
        case .itemType(let t): return t.icon
        case .pageCollection(let c): return c.icon
        case .itemCollection(let c): return c.icon
        }
    }

    private func save(newIcon: String?) async {
        // pendingError is set by each manager on failure; SidebarToast surfaces it.
        switch target {
        case .space(let s):
            do { try await spaceManager.updateIcon(s, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .topic(let t):
            do { try await topicManager.updateTopicIcon(t, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .project(let p):
            do { try await topicManager.updateProjectIcon(p, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .pageType(let t):
            do { try await vaultManager.updatePageTypeIcon(t, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .itemType(let t):
            do { try await itemTypeManager.updateItemTypeIcon(t, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .pageCollection(let c):
            do { try await vaultManager.updatePageCollectionIcon(c, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        case .itemCollection(let c):
            do { try await itemTypeManager.updateItemCollectionIcon(c, to: newIcon) } catch
            { /* pendingError set by manager; toast surfaces */  }
        }
    }
}
