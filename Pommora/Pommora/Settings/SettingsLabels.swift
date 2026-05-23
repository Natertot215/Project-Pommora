import Foundation

struct SettingsLabels: Codable, Equatable, Hashable, Sendable {
    var sidebarSections: SidebarSectionLabels
    var pageType: LabelPair
    var pageCollection: LabelPair
    var itemType: LabelPair
    var itemCollection: LabelPair
    var project: LabelPair
    var agendaTask: LabelPair
    var agendaEvent: LabelPair

    enum CodingKeys: String, CodingKey {
        case sidebarSections = "sidebar_sections"
        case pageType = "page_type"
        case pageCollection = "page_collection"
        case itemType = "item_type"
        case itemCollection = "item_collection"
        case project
        case agendaTask = "agenda_task"
        case agendaEvent = "agenda_event"
    }

    static func defaults() -> SettingsLabels {
        SettingsLabels(
            sidebarSections: SidebarSectionLabels.defaults(),
            pageType: LabelPair(singular: "Vault", plural: "Vaults"),
            pageCollection: LabelPair(singular: "Collection", plural: "Collections"),
            itemType: LabelPair(singular: "Type", plural: "Types"),
            itemCollection: LabelPair(singular: "Set", plural: "Sets"),
            project: LabelPair(singular: "Project", plural: "Projects"),
            agendaTask: LabelPair(singular: "Task", plural: "Tasks"),
            agendaEvent: LabelPair(singular: "Event", plural: "Events")
        )
    }
}

// UI label divergence: Pages-side renders "Vault" / "Collection" (distinctive + generic);
// Items-side renders "Type" / "Set" (generic + distinctive). Each side has one signature
// word + one shared word — visual asymmetry signals which side you're on without echo.
// agendaTask + agendaEvent labels are kept here for Calendar's eventual UI consumption;
// they're dormant in v0.3.0 (no sidebar Agenda section per Phase 8.3).

struct SidebarSectionLabels: Codable, Equatable, Hashable, Sendable {
    var pages: String
    var items: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        SidebarSectionLabels(pages: "Pages", items: "Items")
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}
