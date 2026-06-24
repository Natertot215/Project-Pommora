//
//  ViewPipelineFixtures.swift
//  PommoraTests
//
//  Shared pure-value builders for the ViewPipeline engine tests. No disk, no
//  TempNexus — values in, values out (mirrors OrderResolverTests style).
//

import Foundation

@testable import Pommora

enum VPFixture {
    static func vault(_ id: String = "vault_1", title: String = "Vault") -> PageType {
        PageType(
            id: id, title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func collection(_ id: String, title: String, vault: String = "vault_1") -> PageSet {
        PageSet(
            id: id, parentID: vault, title: title,
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func set(_ id: String, title: String, collection: String) -> PageSet {
        PageSet(
            id: id, parentID: collection, title: title,
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func frontmatter(
        id: String,
        properties: [String: PropertyValue] = [:],
        tier1: [String] = [], tier2: [String] = [], tier3: [String] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0),
        modifiedAt: Date? = nil
    ) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: nil,
            tier1: tier1, tier2: tier2, tier3: tier3,
            properties: properties,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }

    static func meta(
        id: String,
        title: String,
        properties: [String: PropertyValue] = [:],
        tier1: [String] = [], tier2: [String] = [], tier3: [String] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0),
        modifiedAt: Date? = nil
    ) -> PageMeta {
        PageMeta(
            id: id, title: title,
            url: URL(fileURLWithPath: "/\(title).md"),
            frontmatter: frontmatter(
                id: id, properties: properties,
                tier1: tier1, tier2: tier2, tier3: tier3,
                createdAt: createdAt, modifiedAt: modifiedAt
            )
        )
    }

    /// A ViewItem whose page sits directly in a Collection.
    static func item(
        _ id: String, title: String, in collection: PageSet,
        properties: [String: PropertyValue] = [:],
        tier1: [String] = [], modifiedAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> ViewItem {
        ViewItem(
            page: meta(
                id: id, title: title, properties: properties,
                tier1: tier1, createdAt: createdAt, modifiedAt: modifiedAt),
            parent: .collection(collection, vault: vault(collection.parentID)),
            setLabel: nil
        )
    }

    /// A ViewItem whose page sits inside a Set of a Collection.
    static func item(
        _ id: String, title: String, in set: PageSet, of collection: PageSet,
        properties: [String: PropertyValue] = [:]
    ) -> ViewItem {
        ViewItem(
            page: meta(id: id, title: title, properties: properties),
            parent: .set(set, collection: collection, vault: vault(collection.parentID)),
            setLabel: set.title
        )
    }

    /// A ViewItem whose page sits inside a sub-set (Set whose parent is another Set).
    /// `collection` is the depth-1 collection the whole chain ultimately belongs to.
    static func item(
        _ id: String, title: String, inSubSet subSet: PageSet, of collection: PageSet,
        properties: [String: PropertyValue] = [:]
    ) -> ViewItem {
        ViewItem(
            page: meta(id: id, title: title, properties: properties),
            parent: .set(subSet, collection: collection, vault: vault(collection.parentID)),
            setLabel: nil
        )
    }

    /// A ViewItem at the vault root (no Collection).
    static func rootItem(_ id: String, title: String) -> ViewItem {
        ViewItem(
            page: meta(id: id, title: title),
            parent: .vaultRoot(vault()),
            setLabel: nil
        )
    }

    // MARK: - Schema helpers

    static func selectDef(
        _ id: String, name: String, options: [(value: String, label: String)]
    ) -> PropertyDefinition {
        PropertyDefinition(
            id: id, name: name, type: .select,
            selectOptions: options.map {
                PropertyDefinition.SelectOption(value: $0.value, label: $0.label, color: nil)
            }
        )
    }

    static func numberDef(_ id: String, name: String) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .number)
    }

    static func textDef(_ id: String, name: String) -> PropertyDefinition {
        // Modeled as `.select` (single free string) so text operators apply.
        PropertyDefinition(id: id, name: name, type: .select)
    }

    static func dateDef(_ id: String, name: String) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .datetime)
    }

    static func checkboxDef(_ id: String, name: String) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .checkbox)
    }

    static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }
}
