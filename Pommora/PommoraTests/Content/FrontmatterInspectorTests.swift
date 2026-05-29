import Foundation
import Testing

@testable import Pommora

/// Tests for `FrontmatterInspectorViewModel` — the editable inspector (Phase J.14).
/// Tests drive the VM directly (J.5 pattern) to avoid SwiftUI rendering.
/// `onSave` is supplied as a spy closure; no real Page writes occur.
@Suite("FrontmatterInspectorTests")
@MainActor
struct FrontmatterInspectorTests {

    // MARK: - Helpers

    private func makeFrontmatter(
        properties: [String: PropertyValue] = [:],
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = []
    ) -> PageFrontmatter {
        PageFrontmatter(
            id: ULID.generate(),
            icon: nil,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            properties: properties,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: nil
        )
    }

    private func makePageMeta(frontmatter: PageFrontmatter) -> PageMeta {
        PageMeta(
            id: frontmatter.id,
            title: "Test Page",
            url: URL(fileURLWithPath: "/tmp/test.md"),
            frontmatter: frontmatter
        )
    }

    private func makeVault(properties: [PropertyDefinition] = []) -> PageType {
        PageType(
            id: ULID.generate(),
            title: "Test Vault",
            icon: nil,
            properties: properties,
            views: [],
            modifiedAt: Date()
        )
    }

    private func makeDef(
        id: String,
        name: String,
        type: PropertyType = .number
    ) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: type)
    }

    private func makeVM(
        properties: [String: PropertyValue] = [:],
        vaultProps: [PropertyDefinition] = []
    ) -> (vm: FrontmatterInspectorViewModel, saved: () -> [PageFrontmatter]) {
        let frontmatter = makeFrontmatter(properties: properties)
        let page = makePageMeta(frontmatter: frontmatter)
        let vault = makeVault(properties: vaultProps)
        var captured: [PageFrontmatter] = []
        let vm = FrontmatterInspectorViewModel(page: page, vault: vault, onSave: { fm in
            captured.append(fm)
        })
        return (vm, { captured })
    }

    // MARK: - Test 1: each property type renders an editable row (handlePropertyChange)

    @Test("handlePropertyChange updates draftProperties for .number type")
    func numberPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_score", name: "Score", type: .number)])
        vm.handlePropertyChange("prop_score", .number(99.0))
        #expect(vm.draftProperties["prop_score"] == .number(99.0))
    }

    @Test("handlePropertyChange updates draftProperties for .checkbox type")
    func checkboxPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_done", name: "Done", type: .checkbox)])
        vm.handlePropertyChange("prop_done", .checkbox(true))
        #expect(vm.draftProperties["prop_done"] == .checkbox(true))
    }

    @Test("handlePropertyChange updates draftProperties for .select type")
    func selectPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_cat", name: "Category", type: .select)])
        vm.handlePropertyChange("prop_cat", .select("urgent"))
        #expect(vm.draftProperties["prop_cat"] == .select("urgent"))
    }

    @Test("handlePropertyChange updates draftProperties for .multiSelect type")
    func multiSelectPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_tags", name: "Tags", type: .multiSelect)])
        vm.handlePropertyChange("prop_tags", .multiSelect(["a", "b"]))
        #expect(vm.draftProperties["prop_tags"] == .multiSelect(["a", "b"]))
    }

    @Test("handlePropertyChange updates draftProperties for .status type")
    func statusPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_st", name: "Status", type: .status)])
        vm.handlePropertyChange("prop_st", .status("in_progress"))
        #expect(vm.draftProperties["prop_st"] == .status("in_progress"))
    }

    @Test("handlePropertyChange updates draftProperties for .date type")
    func datePropertyEditable() {
        let d = Date(timeIntervalSince1970: 86400)
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_dt", name: "Date", type: .date)])
        vm.handlePropertyChange("prop_dt", .date(d))
        #expect(vm.draftProperties["prop_dt"] == .date(d))
    }

    @Test("handlePropertyChange updates draftProperties for .datetime type")
    func datetimePropertyEditable() {
        let d = Date(timeIntervalSince1970: 86400)
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_dtt", name: "DateTime", type: .datetime)])
        vm.handlePropertyChange("prop_dtt", .datetime(d))
        #expect(vm.draftProperties["prop_dtt"] == .datetime(d))
    }

    @Test("handlePropertyChange updates draftProperties for .url type")
    func urlPropertyEditable() {
        let url = URL(string: "https://example.com")!
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_url", name: "Link", type: .url)])
        vm.handlePropertyChange("prop_url", .url(url))
        #expect(vm.draftProperties["prop_url"] == .url(url))
    }

    @Test("handlePropertyChange updates draftProperties for .relation type")
    func relationPropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_rel", name: "Linked", type: .relation)])
        vm.handlePropertyChange("prop_rel", .relation(["01HREF"]))
        #expect(vm.draftProperties["prop_rel"] == .relation(["01HREF"]))
    }

    @Test("handlePropertyChange updates draftProperties for .file type")
    func filePropertyEditable() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_file", name: "Attach", type: .file)])
        let refs: [FileRef] = []
        vm.handlePropertyChange("prop_file", .file(refs))
        #expect(vm.draftProperties["prop_file"] == .file(refs))
    }

    @Test("handlePropertyChange updates draftProperties for .lastEditedTime (virtual, read-only)")
    func lastEditedTimeAccessible() {
        let (vm, _) = makeVM(vaultProps: [makeDef(id: "prop_let", name: "Modified", type: .lastEditedTime)])
        // lastEditedTime is virtual — handler accepts it without crashing
        vm.handlePropertyChange("prop_let", .lastEditedTime)
        #expect(vm.draftProperties["prop_let"] == .lastEditedTime)
    }

    // MARK: - Test 2: edit triggers a callback to the save handler

    @Test("handlePropertyChange → scheduleSave — flushNow calls onSave with updated frontmatter")
    func editTriggersOnSaveCallback() {
        let (vm, saved) = makeVM(vaultProps: [makeDef(id: "prop_x", name: "X")])
        vm.handlePropertyChange("prop_x", .number(7.0))
        vm.flushNow()  // simulate debounce expiry synchronously

        let calls = saved()
        #expect(calls.count == 1)
        #expect(calls[0].properties["prop_x"] == .number(7.0))
    }

    // MARK: - Test 3: onSave is not called in unit tests if we don't flush

    @Test("onSave callback not called without flushing (mock/spy isolation)")
    func saveMocked() {
        let (vm, saved) = makeVM(vaultProps: [makeDef(id: "prop_y", name: "Y")])
        vm.handlePropertyChange("prop_y", .number(5.0))
        // Do NOT flush — debounce task is pending but has NOT fired
        // (Task.sleep won't complete in a synchronous test loop)
        let calls = saved()
        // Save hasn't fired yet — spy shows no calls
        #expect(calls.isEmpty)
        _ = vm  // keep vm alive
    }

    // MARK: - Test 4: all 11 property types covered

    @Test("All 11 property types can be set via handlePropertyChange without error")
    func allPropertyTypesCovered() {
        let defs: [PropertyDefinition] = [
            makeDef(id: "p1", name: "Number", type: .number),
            makeDef(id: "p2", name: "Checkbox", type: .checkbox),
            makeDef(id: "p3", name: "Date", type: .date),
            makeDef(id: "p4", name: "DateTime", type: .datetime),
            makeDef(id: "p5", name: "Select", type: .select),
            makeDef(id: "p6", name: "MultiSelect", type: .multiSelect),
            makeDef(id: "p7", name: "Status", type: .status),
            makeDef(id: "p8", name: "URL", type: .url),
            makeDef(id: "p9", name: "Relation", type: .relation),
            makeDef(id: "p10", name: "LastEdited", type: .lastEditedTime),
            makeDef(id: "p11", name: "File", type: .file),
        ]
        let (vm, _) = makeVM(vaultProps: defs)

        let now = Date()
        vm.handlePropertyChange("p1", .number(1))
        vm.handlePropertyChange("p2", .checkbox(false))
        vm.handlePropertyChange("p3", .date(now))
        vm.handlePropertyChange("p4", .datetime(now))
        vm.handlePropertyChange("p5", .select("opt"))
        vm.handlePropertyChange("p6", .multiSelect(["a"]))
        vm.handlePropertyChange("p7", .status("done"))
        vm.handlePropertyChange("p8", .url(URL(string: "https://a.com")!))
        vm.handlePropertyChange("p9", .relation(["01HREL"]))
        vm.handlePropertyChange("p10", .lastEditedTime)
        vm.handlePropertyChange("p11", .file([]))

        #expect(vm.draftProperties.count == 11)
    }

    // MARK: - Test 5: schema accessor

    @Test("schemaProperties returns vault.properties")
    func schemaAccessor() {
        let defs = [makeDef(id: "p1", name: "A"), makeDef(id: "p2", name: "B")]
        let (vm, _) = makeVM(vaultProps: defs)
        #expect(vm.schemaProperties.count == 2)
        #expect(vm.schemaProperties[0].id == "p1")
    }
}
