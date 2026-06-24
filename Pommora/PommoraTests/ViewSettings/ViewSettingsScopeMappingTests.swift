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

    @Test("area selection maps to .area scope")
    func areaMapsToArea() {
        let s = Area(
            id: "01HSPACE", title: "Personal", icon: nil,
            blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .area(s))
        #expect(scope == .area)
    }

    @Test("topic selection maps to .topic scope")
    func topicMapsToTopic() {
        let t = Topic(
            id: "01HTOPIC", title: "Work", icon: nil,
            blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .topic(t))
        #expect(scope == .topic)
    }

    @Test("project selection maps to .project scope")
    func projectMapsToProject() {
        let p = Project(
            id: "01HPROJ", title: "Launch",
            icon: nil, blocks: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .project(p))
        #expect(scope == .project)
    }

    @Test("pageCollection selection maps to .pageCollection scope carrying the entity")
    func pageTypeMapsToPageCollection() {
        let t = PageCollection(
            id: "01HPT", title: "Notes", icon: nil, properties: [],
            views: [], modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .pageCollection(t))
        #expect(scope == .pageCollection(t))
    }

    @Test("collection (PageSet) selection maps to .pageCollection scope carrying the entity")
    func collectionMapsToPageSet() {
        let c = PageSet(
            id: "01HPC", parentID: "01HPT", title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/Drafts"),
            modifiedAt: Date()
        )
        let scope = ContentView.viewSettingsScope(for: .collection(c))
        #expect(scope == .pageSet(c))
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

}
