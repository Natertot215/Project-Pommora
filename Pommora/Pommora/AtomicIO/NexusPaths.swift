import Foundation

/// Pure path helpers for every on-disk file the paradigm uses.
/// No I/O except `ensureDirectoryExists`.
enum NexusPaths {

    // MARK: - .nexus/ subdirectories

    static func nexusConfigDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(".nexus", isDirectory: true)
    }

    static func spacesDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("spaces", isDirectory: true)
    }

    static func topicsDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("topics", isDirectory: true)
    }

    // MARK: - Single-file paths inside .nexus/

    static func tierConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("tier-config.json", isDirectory: false)
    }

    static func savedConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("saved-config.json", isDirectory: false)
    }

    static func homepageURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("homepage.json", isDirectory: false)
    }

    // MARK: - Agenda (operational sibling of Vaults)

    static func agendaDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
    }

    static func agendaSchemaURL(in nexus: Nexus) -> URL {
        agendaDir(in: nexus).appendingPathComponent("_agenda.json", isDirectory: false)
    }

    static func agendaItemFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        agendaDir(in: nexus).appendingPathComponent("\(title).agenda.json", isDirectory: false)
    }

    // MARK: - Contexts file paths

    static func spaceFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        spacesDir(in: nexus).appendingPathComponent("\(title).space.json", isDirectory: false)
    }

    static func topicFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicsDir(in: nexus).appendingPathComponent(title, isDirectory: true)
    }

    static func topicMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent("_topic.json", isDirectory: false)
    }

    static func subtopicFileURL(
        forTitle title: String,
        inTopicTitled topicTitle: String,
        in nexus: Nexus
    ) -> URL {
        topicFolderURL(forTitle: topicTitle, in: nexus)
            .appendingPathComponent("\(title).subtopic.json", isDirectory: false)
    }

    // MARK: - Vault / Collection / Content paths

    static func vaultFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(title, isDirectory: true)
    }

    static func vaultMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        vaultFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent("_vault.json", isDirectory: false)
    }

    static func collectionFolderURL(
        forTitle title: String,
        inVaultTitled vaultTitle: String,
        in nexus: Nexus
    ) -> URL {
        vaultFolderURL(forTitle: vaultTitle, in: nexus)
            .appendingPathComponent(title, isDirectory: true)
    }

    static func pageFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).md", isDirectory: false)
    }

    static func itemFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).json", isDirectory: false)
    }

    // MARK: - Filesystem helper

    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
