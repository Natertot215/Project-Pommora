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
    var spaces: String
    var topics: String
    var pages: String
    var items: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        // Section header defaults:
        //   - Pages-side uses its container-plural signature word: "Vaults".
        //   - Items-side uses the operational-concept word "Items" (NOT the
        //     container plural "Types"). Reasoning: the section groups your
        //     Items collection — the user is browsing their Items, not
        //     browsing their Types. Per Nathan's 2026-05-25 directive.
        //   - Both signature words remain renameable via Settings.
        SidebarSectionLabels(spaces: "Spaces", topics: "Topics", pages: "Vaults", items: "Items")
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case spaces, topics, pages, items
    }

    init(spaces: String, topics: String, pages: String, items: String) {
        self.spaces = spaces
        self.topics = topics
        self.pages = pages
        self.items = items
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy files lack `spaces` / `topics` — decode with defaults for
        // backward compatibility. Users who customized will re-apply the label.
        spaces = (try? c.decode(String.self, forKey: .spaces)) ?? "Spaces"
        topics = (try? c.decode(String.self, forKey: .topics)) ?? "Topics"
        pages = try c.decode(String.self, forKey: .pages)
        items = try c.decode(String.self, forKey: .items)
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}
