import Foundation

struct SettingsLabels: Codable, Equatable, Hashable, Sendable {
    var sidebarSections: SidebarSectionLabels
    var pageType: LabelPair
    var pageCollection: LabelPair
    var project: LabelPair
    var agendaTask: LabelPair
    var agendaEvent: LabelPair

    enum CodingKeys: String, CodingKey {
        case sidebarSections = "sidebar_sections"
        case pageType = "page_type"
        case pageCollection = "page_collection"
        case project
        case agendaTask = "agenda_task"
        case agendaEvent = "agenda_event"
    }

    static func defaults() -> SettingsLabels {
        SettingsLabels(
            sidebarSections: SidebarSectionLabels.defaults(),
            pageType: LabelPair(singular: "Vault", plural: "Vaults"),
            pageCollection: LabelPair(singular: "Collection", plural: "Collections"),
            project: LabelPair(singular: "Project", plural: "Projects"),
            agendaTask: LabelPair(singular: "Task", plural: "Tasks"),
            agendaEvent: LabelPair(singular: "Event", plural: "Events")
        )
    }
}

// Pages-side renders the distinctive "Vault" + generic "Collection" pair.
// agendaTask + agendaEvent labels are kept here for Calendar's eventual UI consumption;
// they're dormant in v0.3.0 (no sidebar Agenda section per Phase 8.3).
// Legacy settings.json files may still carry retired Items-side label keys —
// Codable ignores unlisted keys, so they decode cleanly and drop on next write.

struct SidebarSectionLabels: Codable, Equatable, Hashable, Sendable {
    var spaces: String
    var topics: String
    var pages: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        // Pages-side section header defaults to its container-plural signature
        // word "Vaults" — renameable via Settings.
        SidebarSectionLabels(spaces: "Spaces", topics: "Topics", pages: "Vaults")
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case spaces, topics, pages
    }

    init(spaces: String, topics: String, pages: String) {
        self.spaces = spaces
        self.topics = topics
        self.pages = pages
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy files lack `spaces` / `topics` — decode with defaults for
        // backward compatibility. Users who customized will re-apply the label.
        // A retired `items` key may also be present; it's simply not decoded.
        spaces = (try? c.decode(String.self, forKey: .spaces)) ?? "Spaces"
        topics = (try? c.decode(String.self, forKey: .topics)) ?? "Topics"
        pages = try c.decode(String.self, forKey: .pages)
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}
