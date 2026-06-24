import Testing

@testable import Pommora

struct ViewSettingsScopeTests {
    private let vault = Fixtures.pageType(id: "vault_1")
    private let collection = Fixtures.pageCollection(id: "coll_1", parentID: "vault_1")

    @Test func containerIDIsTheEntitysOwnID() {
        #expect(ViewSettingsScope.pageType(vault).containerID == "vault_1")
        #expect(ViewSettingsScope.pageCollection(collection).containerID == "coll_1")
    }

    @Test func schemaTypeIDResolvesToTheOwningVault() {
        #expect(ViewSettingsScope.pageType(vault).schemaTypeID == "vault_1")
        // A Collection's schema lives on its parent Vault — typeID, not its own id.
        #expect(ViewSettingsScope.pageCollection(collection).schemaTypeID == "vault_1")
    }

    @Test func nonContainerScopesResolveToNil() {
        let others: [ViewSettingsScope] = [.none, .page, .area, .topic, .project, .calendar]
        for scope in others {
            #expect(scope.containerID == nil)
            #expect(scope.schemaTypeID == nil)
        }
    }
}
