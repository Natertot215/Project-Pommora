import Foundation
import Testing

@testable import Pommora

/// Tests for Task I.3 — UI label threading.
/// Verifies that `SettingsLabels` has all required keys, defaults match spec,
/// and `SettingsManager.updateLabel` propagates changes so consumers pick them up.
@Suite("UILabelThreadingTests")
@MainActor
struct UILabelThreadingTests {

    // MARK: - Helpers

    private func makeSettingsManager() async throws -> SettingsManager {
        let nexus = try TempNexus.make()
        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        return m
    }

    // MARK: - Test 1: Default labels match SettingsLabels.defaults()

    @Test("Default settings match SettingsLabels.defaults() values")
    func defaultLabelsMatchSpec() async throws {
        let m = try await makeSettingsManager()
        let labels = m.settings.labels
        let defaults = SettingsLabels.defaults()

        #expect(labels.sidebarSections.areas == defaults.sidebarSections.areas)
        #expect(labels.sidebarSections.topics == defaults.sidebarSections.topics)
        #expect(labels.sidebarSections.pages  == defaults.sidebarSections.pages)
        #expect(labels.pageType.singular      == defaults.pageType.singular)
        #expect(labels.pageCollection.singular == defaults.pageCollection.singular)
        #expect(labels.agendaTask.singular    == defaults.agendaTask.singular)
        #expect(labels.agendaEvent.singular   == defaults.agendaEvent.singular)
    }

    // MARK: - Test 2: Default sidebar section values are correct strings

    @Test("Default sidebar section labels are Areas / Topics / Vaults")
    func defaultSidebarSectionStrings() async throws {
        let m = try await makeSettingsManager()
        let s = m.settings.labels.sidebarSections
        #expect(s.areas == "Areas")
        #expect(s.topics == "Topics")
        #expect(s.pages  == "Vaults")
    }

    // MARK: - Test 3: Default page-type label is "Vault"

    @Test("Default pageType label is Vault / Vaults")
    func defaultPageTypeLabel() async throws {
        let m = try await makeSettingsManager()
        #expect(m.settings.labels.pageType.singular == "Vault")
        #expect(m.settings.labels.pageType.plural   == "Vaults")
    }

    // MARK: - Test 4: Customizing the "Vault" label propagates

    @Test("Customizing pageType label persists and is readable on next load")
    func customizeVaultLabelPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        await m.updateLabel(\.pageType, to: LabelPair(singular: "Library", plural: "Libraries"))

        #expect(m.settings.labels.pageType.singular == "Library")

        // Re-read from a second manager instance — verifies on-disk persistence.
        let m2 = SettingsManager(nexus: nexus)
        await m2.loadOrSeed()
        #expect(m2.settings.labels.pageType.singular == "Library")
    }

    // MARK: - Test 5: Customizing the "Areas" section label propagates

    @Test("Customizing sidebarSections.areas persists")
    func customizeAreasSectionLabel() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        var sections = m.settings.labels.sidebarSections
        sections.areas = "Contexts"
        await m.updateLabel(\.sidebarSections, to: sections)

        #expect(m.settings.labels.sidebarSections.areas == "Contexts")

        let m2 = SettingsManager(nexus: nexus)
        await m2.loadOrSeed()
        #expect(m2.settings.labels.sidebarSections.areas == "Contexts")
    }

    // MARK: - Test 6: Untouched labels are preserved when one is updated

    @Test("Updating one label preserves all other labels unchanged")
    func updatingOneLabelPreservesOthers() async throws {
        let m = try await makeSettingsManager()

        await m.updateLabel(\.pageType, to: LabelPair(singular: "Note Folder", plural: "Note Folders"))

        // Untouched labels should be unchanged.
        #expect(m.settings.labels.pageCollection.singular == "Collection")
        #expect(m.settings.labels.agendaTask.singular == "Task")
        #expect(m.settings.labels.sidebarSections.pages == "Vaults")
    }

    // MARK: - Test 7: agendaTask label defaults to "Task"

    @Test("Default agendaTask label is Task / Tasks")
    func defaultAgendaTaskLabel() async throws {
        let m = try await makeSettingsManager()
        #expect(m.settings.labels.agendaTask.singular == "Task")
        #expect(m.settings.labels.agendaTask.plural   == "Tasks")
    }

    // MARK: - Test 8: agendaEvent label defaults to "Event"

    @Test("Default agendaEvent label is Event / Events")
    func defaultAgendaEventLabel() async throws {
        let m = try await makeSettingsManager()
        #expect(m.settings.labels.agendaEvent.singular == "Event")
        #expect(m.settings.labels.agendaEvent.plural   == "Events")
    }

    // MARK: - Test 9: Backward-compatible decode of legacy settings without areas/topics

    @Test("Decoding legacy settings without areas/topics fields uses safe defaults")
    func legacyDecodeHasSafeDefaults() throws {
        // Simulate a legacy settings file that lacks `areas` and `topics`
        // in the sidebar_sections block.
        let json = """
        {
          "version": 1,
          "defaults_version": 1,
          "labels": {
            "sidebar_sections": {
              "pages": "Vaults",
              "items": "Types"
            },
            "page_type": {"singular": "Vault", "plural": "Vaults"},
            "page_collection": {"singular": "Collection", "plural": "Collections"},
            "item_type": {"singular": "Type", "plural": "Types"},
            "item_collection": {"singular": "Set", "plural": "Sets"},
            "project": {"singular": "Project", "plural": "Projects"},
            "agenda_task": {"singular": "Task", "plural": "Tasks"},
            "agenda_event": {"singular": "Event", "plural": "Events"}
          },
          "modified_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Settings.self, from: json)
        #expect(decoded.labels.sidebarSections.areas == "Areas")
        #expect(decoded.labels.sidebarSections.topics == "Topics")
        #expect(decoded.labels.sidebarSections.pages  == "Vaults")
    }
}
