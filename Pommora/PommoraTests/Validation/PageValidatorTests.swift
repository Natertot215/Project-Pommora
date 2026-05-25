import Foundation
import Testing

@testable import Pommora

@Suite("PageValidator")
struct PageValidatorTests {

    @Test("happy path passes")
    func happy() throws {
        let vault = PageType(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            vault: vault,
            context: .empty
        )
    }

    @Test("created_at = zero-epoch is treated as missing")
    func missingCreatedAt() {
        let vault = PageType(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.missingCreatedAt) {
            try PageValidator.validate(
                title: "X",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 0),
                vault: vault,
                context: .empty
            )
        }
    }

    @Test("property with unknown ID throws .unknownProperty(id:)")
    func unknownPropertyIDThrowsWithIDInError() {
        let vault = PageType(
            id: "01HV", title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.unknownProperty(id: "prop_unknown_123")) {
            try PageValidator.validate(
                title: "Notes",
                tier1: [], tier2: [], tier3: [],
                properties: ["prop_unknown_123": .select("A")],
                createdAt: Date(timeIntervalSince1970: 1716000000),
                vault: vault,
                context: .empty
            )
        }
    }

    @Test("property value of wrong type throws .propertyTypeMismatch(id:)")
    func wrongPropertyTypeMismatch() {
        let propID = "prop_count_001"
        let vault = PageType(
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
                vault: vault,
                context: .empty
            )
        }
    }
}
