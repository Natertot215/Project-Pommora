import SwiftUI

/// Read-only frontmatter view for the editor's inspector panel.
///
/// v0.2.7 scope: scaffold the row layout that v0.3.0 Properties will fill in
/// with real editing affordances. Every Page frontmatter field gets a row:
/// title / id / created / icon / tier1/2/3 (resolved to entity names) and
/// each vault-schema property key with a "Coming v0.3.0" placeholder value.
struct FrontmatterInspector: View {
    let page: PageMeta
    let vault: Vault
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Form {
            Section("Page") {
                LabeledContent("Title", value: page.title)
                LabeledContent("ID") {
                    Text(page.frontmatter.id)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Created", value: createdAtFormatted)
                if let icon = page.frontmatter.icon, !icon.isEmpty {
                    LabeledContent("Icon") {
                        Label(icon, systemImage: icon)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Tiers") {
                LabeledContent("Spaces", value: tier1Names)
                LabeledContent("Topics", value: tier2Names)
                LabeledContent("Sub-topics", value: tier3Names)
            }

            Section("Properties") {
                if vault.properties.isEmpty {
                    Text("No properties defined in this Vault's schema.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vault.properties) { prop in
                        LabeledContent(prop.name) {
                            Text("Coming v0.3.0")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Resolvers

    private var createdAtFormatted: String {
        page.frontmatter.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var tier1Names: String {
        let names = page.frontmatter.tier1.compactMap { id in
            spaceManager.spaces.first { $0.id == id }?.title
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var tier2Names: String {
        // TopicManager isn't injected here in v0.2.7; surfacing "(N)" count.
        // Full resolution lands when v0.3.0 Properties flesh out the inspector.
        page.frontmatter.tier2.isEmpty ? "—" : "(\(page.frontmatter.tier2.count))"
    }

    private var tier3Names: String {
        page.frontmatter.tier3.isEmpty ? "—" : "(\(page.frontmatter.tier3.count))"
    }
}
