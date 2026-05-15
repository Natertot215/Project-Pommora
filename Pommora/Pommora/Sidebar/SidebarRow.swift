//
//  SidebarRow.swift
//  Pommora
//

import SwiftUI

/// A single sidebar entry — folder, page, or item — rendered as `Label`
/// (icon + name). Names already have extensions stripped by `SidebarNode`.
///
/// SF Symbols are placeholders: the symbol-registry decision (per-entity-
/// type icon mapping) is parked as a separate brainstorm. When that lands,
/// only this view changes.
struct SidebarRow: View {
    let node: SidebarNode

    var body: some View {
        Label(node.name, systemImage: iconName)
    }

    private var iconName: String {
        switch node.kind {
        case .folder: return "folder"
        case .page:   return "doc.text"
        case .item:   return "list.bullet.rectangle"
        }
    }
}
