import GRDB

enum IndexSchema {
    /// Apply all DDL to the given database. Idempotent (uses CREATE TABLE IF NOT EXISTS).
    static func apply(to db: Database) throws {
        try db.execute(sql: pageTypesDDL)
        try db.execute(sql: pageCollectionsDDL)
        try db.execute(sql: pagesDDL)
        try db.execute(sql: agendaTasksDDL)
        try db.execute(sql: agendaEventsDDL)
        try db.execute(sql: contextsDDL)
        try db.execute(sql: contextLinksDDL)
        try db.execute(sql: connectionsDDL)
        try db.execute(sql: propertyDefinitionsDDL)
        try db.execute(sql: indexesDDL)
    }

    // MARK: - Table DDL

    private static let pageTypesDDL = """
        CREATE TABLE IF NOT EXISTS page_types (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            icon TEXT,
            modified_at TEXT NOT NULL,
            schema_version INTEGER NOT NULL DEFAULT 1
        );
        """

    private static let pageCollectionsDDL = """
        CREATE TABLE IF NOT EXISTS page_collections (
            id TEXT PRIMARY KEY,
            page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            icon TEXT,
            modified_at TEXT NOT NULL,
            schema_version INTEGER NOT NULL DEFAULT 1
        );
        """

    private static let pagesDDL = """
        CREATE TABLE IF NOT EXISTS pages (
            id TEXT PRIMARY KEY,
            page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
            page_collection_id TEXT REFERENCES page_collections(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            icon TEXT,
            properties TEXT NOT NULL DEFAULT '{}',
            modified_at TEXT NOT NULL
        );
        """

    private static let agendaTasksDDL = """
        CREATE TABLE IF NOT EXISTS agenda_tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            icon TEXT,
            due_at TEXT,
            properties TEXT NOT NULL DEFAULT '{}',
            modified_at TEXT NOT NULL
        );
        """

    private static let agendaEventsDDL = """
        CREATE TABLE IF NOT EXISTS agenda_events (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            icon TEXT,
            start_at TEXT NOT NULL,
            end_at TEXT NOT NULL,
            properties TEXT NOT NULL DEFAULT '{}',
            modified_at TEXT NOT NULL
        );
        """

    private static let contextsDDL = """
        CREATE TABLE IF NOT EXISTS contexts (
            id TEXT PRIMARY KEY,
            tier INTEGER NOT NULL,
            title TEXT NOT NULL,
            icon TEXT
        );
        """

    private static let contextLinksDDL = """
        CREATE TABLE IF NOT EXISTS context_links (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            target_id TEXT NOT NULL,
            target_kind TEXT NOT NULL,
            property_id TEXT NOT NULL,
            modified_at TEXT NOT NULL
        );
        """

    private static let connectionsDDL = """
        CREATE TABLE IF NOT EXISTS connections (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            source_kind TEXT NOT NULL,          -- always "page" (connections are page-only)
            target_id TEXT,                     -- NULL while phantom (unresolved)
            target_kind TEXT NOT NULL,          -- always "page" (from [[ ]])
            target_title TEXT NOT NULL,         -- normalized (trimmed+lowercased) — resolution key
            surface TEXT NOT NULL,              -- always "page_body"
            multiplicity INTEGER NOT NULL DEFAULT 1,
            weight REAL NOT NULL DEFAULT 1.0,
            resolved INTEGER NOT NULL DEFAULT 0,
            modified_at TEXT NOT NULL
        );
        """

    private static let propertyDefinitionsDDL = """
        CREATE TABLE IF NOT EXISTS property_definitions (
            id TEXT PRIMARY KEY,
            owning_type_id TEXT NOT NULL,
            owning_type_kind TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            config TEXT NOT NULL DEFAULT '{}',
            position INTEGER NOT NULL DEFAULT 0,
            modified_at TEXT NOT NULL
        );
        """

    // MARK: - Indexes DDL

    private static let indexesDDL = """
        CREATE INDEX IF NOT EXISTS idx_pages_page_type_id ON pages(page_type_id);
        CREATE INDEX IF NOT EXISTS idx_pages_page_collection_id ON pages(page_collection_id);
        CREATE INDEX IF NOT EXISTS idx_page_collections_page_type_id ON page_collections(page_type_id);
        CREATE INDEX IF NOT EXISTS idx_context_links_source_id ON context_links(source_id);
        CREATE INDEX IF NOT EXISTS idx_context_links_target_id ON context_links(target_id);
        CREATE INDEX IF NOT EXISTS idx_context_links_property_id ON context_links(property_id);
        CREATE INDEX IF NOT EXISTS idx_property_definitions_owning_type ON property_definitions(owning_type_id, owning_type_kind);
        CREATE INDEX IF NOT EXISTS idx_contexts_tier ON contexts(tier);
        CREATE INDEX IF NOT EXISTS idx_connections_source_id ON connections(source_id);
        CREATE INDEX IF NOT EXISTS idx_connections_target_id ON connections(target_id);
        CREATE INDEX IF NOT EXISTS idx_connections_target_title ON connections(target_kind, target_title);
        CREATE INDEX IF NOT EXISTS idx_pages_title ON pages(title COLLATE NOCASE);
        """
}
