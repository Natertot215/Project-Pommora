import Foundation
import Testing
@testable import Pommora

@Suite struct PropertyTypeTests {
    @Test func decodesStatusCase() throws {
        let json = #""status""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyType.self, from: json)
        #expect(decoded == .status)
    }

    @Test func decodesLastEditedTimeCase() throws {
        let json = #""last_edited_time""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyType.self, from: json)
        #expect(decoded == .lastEditedTime)
    }

    @Test func decodesFileCase() throws {
        let json = #""file""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyType.self, from: json)
        #expect(decoded == .file)
    }

    @Test func encodesAllElevenCases() throws {
        let cases: [(PropertyType, String)] = [
            (.number, "number"), (.checkbox, "checkbox"),
            (.date, "date"), (.datetime, "datetime"),
            (.select, "select"), (.multiSelect, "multi_select"),
            (.status, "status"), (.url, "url"),
            (.relation, "relation"), (.lastEditedTime, "last_edited_time"),
            (.file, "file"),
        ]
        for (kase, expected) in cases {
            let data = try JSONEncoder().encode(kase)
            let s = String(data: data, encoding: .utf8)
            #expect(s == #""\#(expected)""#)
        }
    }
}
