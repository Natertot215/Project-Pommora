import Foundation
import Testing

@testable import Pommora

@Suite struct IndexDateFormatTests {
    @Test func index_datetime_format_is_consistent_across_read_and_write() {
        let d = Date(timeIntervalSince1970: 1_700_000_000.123)
        // Both must include fractional seconds so a datetime filter matches a stored timestamp.
        #expect(IndexDateFormat.iso8601.string(from: d).contains("."))
    }
}
