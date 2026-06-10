import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("SettingsManager")
struct SettingsManagerTests {

    @Test("loadOrSeed writes defaults to disk on first launch")
    func seedsOnFirstLaunch() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = NexusPaths.settingsFileURL(in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(m.settings.version == 1)
        #expect(m.settings.accentColor == nil)
        #expect(m.settings.labels.pageType.singular == "Vault")
        #expect(m.settings.labels.pageCollection.singular == "Collection")
        #expect(m.pendingError == nil)
    }

    @Test("loadOrSeed decodes an existing settings.json")
    func loadsExistingFile() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Write a pre-existing settings file with a non-default accent + label.
        var seeded = Settings.defaultSeed()
        seeded.accentColor = .green
        seeded.labels.pageType = LabelPair(singular: "Library", plural: "Libraries")
        try AtomicJSON.write(seeded, to: NexusPaths.settingsFileURL(in: nexus))

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.settings.accentColor == .green)
        #expect(m.settings.labels.pageType.singular == "Library")
        #expect(m.pendingError == nil)
    }

    @Test("updateAccentColor mutates and persists")
    func updateAccentColorPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        let original = m.settings.modifiedAt

        await m.updateAccentColor(.red)

        #expect(m.settings.accentColor == .red)
        #expect(m.settings.modifiedAt >= original)

        // Verify on-disk persistence.
        let reloaded = try AtomicJSON.decode(
            Settings.self,
            from: NexusPaths.settingsFileURL(in: nexus)
        )
        #expect(reloaded.accentColor == .red)
    }

    @Test("updateAccentColor(nil) clears the override")
    func updateAccentColorClear() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        await m.updateAccentColor(.purple)
        #expect(m.settings.accentColor == .purple)

        await m.updateAccentColor(nil)
        #expect(m.settings.accentColor == nil)

        let reloaded = try AtomicJSON.decode(
            Settings.self,
            from: NexusPaths.settingsFileURL(in: nexus)
        )
        #expect(reloaded.accentColor == nil)
    }

    @Test("updateLabel mutates and persists a LabelPair via keyPath")
    func updateLabelPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        let newLabel = LabelPair(singular: "Library", plural: "Libraries")
        await m.updateLabel(\.pageType, to: newLabel)

        #expect(m.settings.labels.pageType == newLabel)

        let reloaded = try AtomicJSON.decode(
            Settings.self,
            from: NexusPaths.settingsFileURL(in: nexus)
        )
        #expect(reloaded.labels.pageType.singular == "Library")
        #expect(reloaded.labels.pageType.plural == "Libraries")
    }

    @Test("updateLabel preserves untouched label pairs")
    func updateLabelPreservesOthers() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        let todo = LabelPair(singular: "Todo", plural: "Todos")
        await m.updateLabel(\.agendaTask, to: todo)

        #expect(m.settings.labels.agendaTask == todo)
        // Pages-side labels stay default.
        #expect(m.settings.labels.pageType.singular == "Vault")
        #expect(m.settings.labels.pageCollection.singular == "Collection")
        // Sibling Agenda label stays default.
        #expect(m.settings.labels.agendaEvent.singular == "Event")
    }

    @Test("modifiedAt advances on each mutation")
    func modifiedAtAdvances() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        let t0 = m.settings.modifiedAt

        // Sleep ~10ms so the second timestamp is strictly later, not just
        // equal — Date resolution on macOS is sub-microsecond but tests are
        // friendlier with a non-zero gap.
        try await Task.sleep(nanoseconds: 10_000_000)
        await m.updateAccentColor(.blue)
        let t1 = m.settings.modifiedAt
        #expect(t1 > t0)

        try await Task.sleep(nanoseconds: 10_000_000)
        await m.updateLabel(\.project, to: LabelPair(singular: "Initiative", plural: "Initiatives"))
        let t2 = m.settings.modifiedAt
        #expect(t2 > t1)
    }

    @Test("two managers on the same nexus see persisted state")
    func twoManagersShareState() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let first = SettingsManager(nexus: nexus)
        await first.loadOrSeed()
        await first.updateAccentColor(.orange)
        await first.updateLabel(\.pageType, to: LabelPair(singular: "Kind", plural: "Kinds"))

        let second = SettingsManager(nexus: nexus)
        await second.loadOrSeed()
        #expect(second.settings.accentColor == .orange)
        #expect(second.settings.labels.pageType.singular == "Kind")
    }
}
