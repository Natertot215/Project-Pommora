import Foundation

struct SettingsLabels: Codable, Equatable, Hashable, Sendable {
    var sidebarSections: SidebarSectionLabels
    var pageType: LabelPair
    var pageCollection: LabelPair
    var pageSet: LabelPair
    var project: LabelPair
    var agendaTask: LabelPair
    var agendaEvent: LabelPair

    enum CodingKeys: String, CodingKey {
        case sidebarSections = "sidebar_sections"
        case pageType = "page_type"
        case pageCollection = "page_collection"
        case pageSet = "page_set"
        case project
        case agendaTask = "agenda_task"
        case agendaEvent = "agenda_event"
    }

    static func defaults() -> SettingsLabels {
        SettingsLabels(
            sidebarSections: SidebarSectionLabels.defaults(),
            pageType: LabelPair(singular: "Vault", plural: "Vaults"),
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
        pageType: LabelPair,
        pageCollection: LabelPair,
        pageSet: LabelPair,
        project: LabelPair,
        agendaTask: LabelPair,
        agendaEvent: LabelPair
    ) {
        self.sidebarSections = sidebarSections
        self.pageType = pageType
        self.pageCollection = pageCollection
        self.pageSet = pageSet
        self.project = project
        self.agendaTask = agendaTask
        self.agendaEvent = agendaEvent
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sidebarSections = try c.decode(SidebarSectionLabels.self, forKey: .sidebarSections)
        pageType = try c.decode(LabelPair.self, forKey: .pageType)
        pageCollection = try c.decode(LabelPair.self, forKey: .pageCollection)
        // Older files lack `page_set` — decode with the default, mirroring
        // SidebarSectionLabels' areas/topics. The decoded value equals the
        // new default, so no defaultsVersion bump or migration step needed.
        pageSet =
            (try? c.decode(LabelPair.self, forKey: .pageSet))
            ?? LabelPair(singular: "Set", plural: "Sets")
        project = try c.decode(LabelPair.self, forKey: .project)
        agendaTask = try c.decode(LabelPair.self, forKey: .agendaTask)
        agendaEvent = try c.decode(LabelPair.self, forKey: .agendaEvent)
    }
}

// Pages-side renders the distinctive "Vault" + generic "Collection" pair.
// agendaTask + agendaEvent labels are kept here for Calendar's eventual UI consumption;
// they're dormant in v0.3.0 (no sidebar Agenda section per Phase 8.3).
// Legacy settings.json files may still carry retired label keys —
// Codable ignores unlisted keys, so they decode cleanly and drop on next write.

struct SidebarSectionLabels: Codable, Equatable, Hashable, Sendable {
    var areas: String
    var topics: String
    var pages: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        // Pages-side section header defaults to its container-plural signature
        // word "Vaults" — renameable via Settings.
        SidebarSectionLabels(areas: "Areas", topics: "Topics", pages: "Vaults")
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
        pages = try c.decode(String.self, forKey: .pages)
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}
