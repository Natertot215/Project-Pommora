//
//  Nexus.swift
//  Pommora
//

import Foundation

/// A Pommora Nexus: a user-picked folder that holds the canonical content
/// (Pages, Collections, Areas) plus a hidden `.nexus/` config folder
/// at its root.
///
/// The id is a ULID stored in `.nexus/nexus.json`; it survives the nexus
/// folder being renamed or moved on disk.
struct Nexus: Equatable, Hashable, Identifiable {
    let id: String
    let rootURL: URL
}
