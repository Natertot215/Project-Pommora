import Foundation
import Testing

@testable import Pommora

@Suite("PageValidator")
struct PageValidatorTests {

    @Test("happy path passes")
    func happy() throws {
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            pageCollection: vault,
            context: .empty
        )
    }

    @Test("created_at = zero-epoch is treated as missing")
    func missingCreatedAt() {
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.missingCreatedAt) {
            try PageValidator.validate(
                title: "X",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 0),
                pageCollection: vault,
                context: .empty
            )
        }
    }

    @Test("property with unknown ID throws .unknownProperty(id:)")
    func unknownPropertyIDThrowsWithIDInError() {
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.unknownProperty(id: "prop_unknown_123")) {
            try PageValidator.validate(
                title: "Notes",
                tier1: [], tier2: [], tier3: [],
                properties: ["prop_unknown_123": .select("A")],
                createdAt: Date(timeIntervalSince1970: 1716000000),
                pageCollection: vault,
                context: .empty
            )
        }
    }

    @Test("property value of wrong type throws .propertyTypeMismatch(id:)")
    func wrongPropertyTypeMismatch() {
        let propID = "prop_count_001"
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [
                PropertyDefinition(id: propID, name: "count", type: .number)
            ],
            views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.propertyTypeMismatch(id: propID)) {
            try PageValidator.validate(
                title: "Notes",
                tier1: [], tier2: [], tier3: [],
                properties: [propID: .checkbox(true)],
                createdAt: Date(timeIntervalSince1970: 1716000000),
                pageCollection: vault,
                context: .empty
            )
        }
    }

    @Test("status value against a status property passes (the gap that bricked legacy-item saves)")
    func statusValueAgainstStatusType() throws {
        let propID = "prop_status_001"
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [
                PropertyDefinition(
                    id: propID, name: "Status", type: .status,
                    statusGroups: PropertyDefinition.StatusGroup.defaultSeed())
            ],
            views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [propID: .status("in_progress")],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            pageCollection: vault,
            context: .empty
        )
    }

    @Test("file value against a file property passes")
    func fileValueAgainstFileType() throws {
        let propID = "prop_file_001"
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [
                PropertyDefinition(id: propID, name: "Attachments", type: .file)
            ],
            views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [propID: .file([])],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            pageCollection: vault,
            context: .empty
        )
    }

    @Test("status value against a select property still mismatches")
    func statusValueAgainstSelectTypeMismatches() {
        let propID = "prop_pick_001"
        let vault = PageCollection(
            id: "01HV", title: "V", icon: nil,
            properties: [
                PropertyDefinition(id: propID, name: "Pick", type: .select)
            ],
            views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.propertyTypeMismatch(id: propID)) {
            try PageValidator.validate(
                title: "Notes",
                tier1: [], tier2: [], tier3: [],
                properties: [propID: .status("done")],
                createdAt: Date(timeIntervalSince1970: 1716000000),
                pageCollection: vault,
                context: .empty
            )
        }
    }
}
