import Foundation
import Testing

@testable import Pommora

@Suite("ViewSettingsScope mapping from SidebarSelection")
@MainActor
struct ViewSettingsScopeMappingTests {

    @Test("none selection maps to .none scope")
    func noneMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .none)
        #expect(scope == .none)
    }

    @Test("savedKey calendar maps to .calendar scope")
    func calendarSavedKeyMapsToCalendar() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("calendar"))
        #expect(scope == .calendar)
    }

    @Test("savedKey homepage maps to .none scope (not a view-settings surface)")
    func homepageSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("homepage"))
        #expect(scope == .none)
    }

    @Test("savedKey recents maps to .none scope (not a view-settings surface)")
    func recentsSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("recents"))
        #expect(scope == .none)
    }

    @Test("savedKey unknown maps to .none scope")
    func unknownSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("garbage"))
        #expect(scope == .none)
    }

    @Test("space selection maps to .space scope")
    func spaceMapsToSpace() {
        let s = Space(
            id: "01HSPACE", title: "Personal", color: nil, icon: nil,
            blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .space(s))
        #expect(scope == .space)
    }

    @Test("topic selection maps to .topic scope")
    func topicMapsToTopic() {
        let t = Topic(
            id: "01HTOPIC", title: "Work", parents: [], icon: nil,
            blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .topic(t))
        #expect(scope == .topic)
    }

    @Test("project selection maps to .project scope")
    func projectMapsToProject() {
        let p = Project(
            id: "01HPROJ", title: "Launch", parents: [], projectLinks: [],
            icon: nil, blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .project(p))
        #expect(scope == .project)
    }

    @Test("pageType selection maps to .pageType scope carrying the entity")
    func pageTypeMapsToPageType() {
        let t = PageType(
            id: "01HPT", title: "Notes", icon: nil, properties: [],
            views: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .pageType(t))
        #expect(scope == .pageType(t))
    }

    @Test("collection (PageCollection) selection maps to .pageCollection scope carrying the entity")
    func collectionMapsToPageCollection() {
        let c = PageCollection(
            id: "01HPC", typeID: "01HPT", title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/Drafts"),
            modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .collection(c))
        #expect(scope == .pageCollection(c))
    }

    @Test("page selection maps to .page scope")
    func pageMapsToPage() {
        let frontmatter = PageFrontmatter(
            id: "01HPAGE", icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        let p = PageMeta(
            id: "01HPAGE", title: "Notes",
            url: URL(fileURLWithPath: "/tmp/Notes.md"),
            frontmatter: frontmatter
        )
        let scope = ContentView.viewSettingsScope(for: .page(p))
        #expect(scope == .page)
    }

    @Test("itemType selection maps to .itemType scope carrying the entity")
    func itemTypeMapsToItemType() {
        let t = ItemType(
            id: "01HIT", title: "Books", icon: nil, properties: [],
            views: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .itemType(t))
        #expect(scope == .itemType(t))
    }

    @Test("itemCollection selection maps to .itemCollection scope carrying the entity")
    func itemCollectionMapsToItemCollection() {
        let c = ItemCollection(
            id: "01HIC", typeID: "01HIT", title: "Want to read",
            folderURL: URL(fileURLWithPath: "/tmp/Want to read"),
            modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .itemCollection(c))
        #expect(scope == .itemCollection(c))
    }
}
