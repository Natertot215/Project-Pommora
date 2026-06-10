import Foundation
import Testing
@testable import Pommora

// MARK: - PageFrontmatter

@Suite("TierValueAdapter — PageFrontmatter")
struct TierValueAdapterPageFrontmatterTests {

    private func makeFrontmatter(
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = [],
        properties: [String: PropertyValue] = [:]
    ) -> PageFrontmatter {
        PageFrontmatter(
            id: "01HFMT",
            icon: nil,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            properties: properties,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: Tier reads map to root fields

    @Test func tier1ReadFromRoot() {
        let fm = makeFrontmatter(tier1: ["01A"])
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier1) == ["01A"])
    }

    @Test func tier2ReadFromRoot() {
        let fm = makeFrontmatter(tier2: ["01B"])
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier2) == ["01B"])
    }

    @Test func tier3ReadFromRoot() {
        let fm = makeFrontmatter(tier3: ["01C"])
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier3) == ["01C"])
    }

    @Test func tierReadReturnsEmptyWhenRootIsEmpty() {
        let fm = makeFrontmatter()
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier1) == [])
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier2) == [])
        #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier3) == [])
    }

    // MARK: Tier writes route to root fields

    @Test func tier1WriteUpdatesRootField() {
        var fm = makeFrontmatter()
        fm.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier1)
        #expect(fm.tier1 == ["01A", "01B"])
        #expect(fm.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test func tier2WriteUpdatesRootField() {
        var fm = makeFrontmatter()
        fm.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier2)
        #expect(fm.tier2 == ["01A", "01B"])
        #expect(fm.properties[ReservedPropertyID.tier2] == nil)
    }

    @Test func tier3WriteUpdatesRootField() {
        var fm = makeFrontmatter()
        fm.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier3)
        #expect(fm.tier3 == ["01A", "01B"])
        #expect(fm.properties[ReservedPropertyID.tier3] == nil)
    }

    // MARK: User relation round-trip

    @Test func userRelationWriteThenRead() {
        var fm = makeFrontmatter()
        fm.setRelationIDs(["01T"], forPropertyID: "prop_rel")
        #expect(fm.relationIDs(forPropertyID: "prop_rel") == ["01T"])
        #expect(fm.properties["prop_rel"] == .relation(["01T"]))
    }

    @Test func emptyUserRelationOmitsKey() {
        var fm = makeFrontmatter(properties: ["prop_rel": .relation(["01T"])])
        fm.setRelationIDs([], forPropertyID: "prop_rel")
        #expect(fm.properties["prop_rel"] == nil)
    }

    @Test func unknownPropertyIDReturnsEmpty() {
        let fm = makeFrontmatter()
        #expect(fm.relationIDs(forPropertyID: "prop_unknown") == [])
    }
}

// MARK: - AgendaTask

@Suite("TierValueAdapter — AgendaTask")
struct TierValueAdapterAgendaTaskTests {

    private func makeTask(
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = [],
        properties: [String: PropertyValue] = [:]
    ) -> AgendaTask {
        AgendaTask(
            id: "01HTASK",
            title: "Test Task",
            icon: nil,
            description: "",
            dueAt: nil,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: false,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            properties: properties
        )
    }

    // MARK: Tier reads map to root fields

    @Test func tier1ReadFromRoot() {
        let task = makeTask(tier1: ["01A"])
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier1) == ["01A"])
    }

    @Test func tier2ReadFromRoot() {
        let task = makeTask(tier2: ["01B"])
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier2) == ["01B"])
    }

    @Test func tier3ReadFromRoot() {
        let task = makeTask(tier3: ["01C"])
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier3) == ["01C"])
    }

    @Test func tierReadReturnsEmptyWhenRootIsEmpty() {
        let task = makeTask()
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier1) == [])
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier2) == [])
        #expect(task.relationIDs(forPropertyID: ReservedPropertyID.tier3) == [])
    }

    // MARK: Tier writes route to root fields

    @Test func tier1WriteUpdatesRootField() {
        var task = makeTask()
        task.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier1)
        #expect(task.tier1 == ["01A", "01B"])
        #expect(task.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test func tier2WriteUpdatesRootField() {
        var task = makeTask()
        task.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier2)
        #expect(task.tier2 == ["01A", "01B"])
        #expect(task.properties[ReservedPropertyID.tier2] == nil)
    }

    // MARK: User relation round-trip

    @Test func userRelationWriteThenRead() {
        var task = makeTask()
        task.setRelationIDs(["01T"], forPropertyID: "prop_rel")
        #expect(task.relationIDs(forPropertyID: "prop_rel") == ["01T"])
        #expect(task.properties["prop_rel"] == .relation(["01T"]))
    }

    @Test func emptyUserRelationOmitsKey() {
        var task = makeTask(properties: ["prop_rel": .relation(["01T"])])
        task.setRelationIDs([], forPropertyID: "prop_rel")
        #expect(task.properties["prop_rel"] == nil)
    }
}

// MARK: - AgendaEvent

@Suite("TierValueAdapter — AgendaEvent")
struct TierValueAdapterAgendaEventTests {

    private func makeEvent(
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = [],
        properties: [String: PropertyValue] = [:]
    ) -> AgendaEvent {
        AgendaEvent(
            id: "01HEVENT",
            title: "Test Event",
            icon: nil,
            description: "",
            startAt: Date(timeIntervalSince1970: 1_716_480_000),
            endAt: Date(timeIntervalSince1970: 1_716_481_800),
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            properties: properties
        )
    }

    // MARK: Tier reads map to root fields

    @Test func tier1ReadFromRoot() {
        let event = makeEvent(tier1: ["01A"])
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier1) == ["01A"])
    }

    @Test func tier2ReadFromRoot() {
        let event = makeEvent(tier2: ["01B"])
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier2) == ["01B"])
    }

    @Test func tier3ReadFromRoot() {
        let event = makeEvent(tier3: ["01C"])
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier3) == ["01C"])
    }

    @Test func tierReadReturnsEmptyWhenRootIsEmpty() {
        let event = makeEvent()
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier1) == [])
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier2) == [])
        #expect(event.relationIDs(forPropertyID: ReservedPropertyID.tier3) == [])
    }

    // MARK: Tier writes route to root fields

    @Test func tier1WriteUpdatesRootField() {
        var event = makeEvent()
        event.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier1)
        #expect(event.tier1 == ["01A", "01B"])
        #expect(event.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test func tier2WriteUpdatesRootField() {
        var event = makeEvent()
        event.setRelationIDs(["01A", "01B"], forPropertyID: ReservedPropertyID.tier2)
        #expect(event.tier2 == ["01A", "01B"])
        #expect(event.properties[ReservedPropertyID.tier2] == nil)
    }

    // MARK: User relation round-trip

    @Test func userRelationWriteThenRead() {
        var event = makeEvent()
        event.setRelationIDs(["01T"], forPropertyID: "prop_rel")
        #expect(event.relationIDs(forPropertyID: "prop_rel") == ["01T"])
        #expect(event.properties["prop_rel"] == .relation(["01T"]))
    }

    @Test func emptyUserRelationOmitsKey() {
        var event = makeEvent(properties: ["prop_rel": .relation(["01T"])])
        event.setRelationIDs([], forPropertyID: "prop_rel")
        #expect(event.properties["prop_rel"] == nil)
    }
}
