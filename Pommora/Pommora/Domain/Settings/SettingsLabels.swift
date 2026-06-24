import Foundation

struct SettingsLabels: Codable, Equatable, Hashable, Sendable {
    var sidebarSections: SidebarSectionLabels
    /// Top-tier Pages label (user-facing "Collection"). Formerly `page_type` / "Vault".
    var pageCollection: LabelPair
    /// Recursive Set label. Nested Sets derive "Sub-Set" as `"Sub-" + pageSet.singular` — not stored.
    var pageSet: LabelPair
    var project: LabelPair
    var agendaTask: LabelPair
    var agendaEvent: LabelPair

    enum CodingKeys: String, CodingKey {
        case sidebarSections = "sidebar_sections"
        case pageCollection = "page_collection"
        case pageSet = "page_set"
        case project
        case agendaTask = "agenda_task"
        case agendaEvent = "agenda_event"
    }

    static func defaults() -> SettingsLabels {
        SettingsLabels(
            sidebarSections: SidebarSectionLabels.defaults(),
            pageCollection: LabelPair(singular: "Collection", plural: "Collections"),
            pageSet: LabelPair(singular: "Set", plural: "Sets"),
            project: LabelPair(singular: "Project", plural: "Projects"),
            agendaTask: LabelPair(singular: "Task", plural: "Tasks"),
            agendaEvent: LabelPair(singular: "Event", plural: "Events")
        )
    }

    // MARK: - Codable

    init(
        sidebarSections: SidebarSectionLabels,
        pageCollection: LabelPair,
        pageSet: LabelPair,
        project: LabelPair,
        agendaTask: LabelPair,
        agendaEvent: LabelPair
    ) {
        self.sidebarSections = sidebarSections
        self.pageCollection = pageCollection
        self.pageSet = pageSet
        self.project = project
        self.agendaTask = agendaTask
        self.agendaEvent = agendaEvent
    }

    // Used only during decoding to read the retired `page_type` key from old files.
    private enum LegacyCodingKeys: String, CodingKey {
        case pageType = "page_type"
    }

    private static let oldPageTypeDefault = LabelPair(singular: "Vault", plural: "Vaults")
    private static let newPageCollectionDefault = LabelPair(singular: "Collection", plural: "Collections")

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sidebarSections = try c.decode(SidebarSectionLabels.self, forKey: .sidebarSections)
        // Old files carry `page_type` (top tier) + `page_collection` (middle tier).
        // If `page_type` is present and the user customized it off "Vault", carry
        // it into `pageCollection`. If it was the default "Vault" (or absent),
        // use `page_collection` for new-format files, or the new default otherwise.
        pageCollection = Self.resolvePageCollection(from: decoder, primaryContainer: c)
        pageSet =
            (try? c.decode(LabelPair.self, forKey: .pageSet))
            ?? LabelPair(singular: "Set", plural: "Sets")
        project = try c.decode(LabelPair.self, forKey: .project)
        agendaTask = try c.decode(LabelPair.self, forKey: .agendaTask)
        agendaEvent = try c.decode(LabelPair.self, forKey: .agendaEvent)
    }

    private static func resolvePageCollection(
        from decoder: any Decoder,
        primaryContainer c: KeyedDecodingContainer<CodingKeys>
    ) -> LabelPair {
        // Try to read the retired `page_type` key (exists in old three-tier files).
        if let legacyC = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           let oldPageType = try? legacyC.decodeIfPresent(LabelPair.self, forKey: .pageType)
        {
            // User customized the top tier off "Vault" → carry the value forward.
            if oldPageType != Self.oldPageTypeDefault {
                return oldPageType
            }
            // Old default "Vault" → migrate to new default "Collection".
            return Self.newPageCollectionDefault
        }
        // New-format file: `page_collection` already holds the top-tier label.
        return (try? c.decode(LabelPair.self, forKey: .pageCollection)) ?? Self.newPageCollectionDefault
    }
}

// agendaTask + agendaEvent labels are kept for Calendar's eventual UI consumption.

struct SidebarSectionLabels: Codable, Equatable, Hashable, Sendable {
    var areas: String
    var topics: String
    var pages: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        SidebarSectionLabels(areas: "Areas", topics: "Topics", pages: "Collections")
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case areas, topics, pages
    }

    init(areas: String, topics: String, pages: String) {
        self.areas = areas
        self.topics = topics
        self.pages = pages
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy files lack `areas` / `topics` — decode with defaults for
        // backward compatibility. Users who customized will re-apply the label.
        // A retired section key may also be present; it's simply not decoded.
        areas = (try? c.decode(String.self, forKey: .areas)) ?? "Areas"
        topics = (try? c.decode(String.self, forKey: .topics)) ?? "Topics"
        pages = (try? c.decode(String.self, forKey: .pages)) ?? "Collections"
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}
