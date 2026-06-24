import Foundation
import Testing

@testable import Pommora

@Suite("ManagerErrorMessage")
struct ManagerErrorMessageTests {

    /// `.localizedDescription` must NOT contain the raw type name. Pre-fix the
    /// bridged string is "Pommora.PageCollectionManagerError error 1"; post-fix the
    /// `LocalizedError.errorDescription` text replaces it.
    @Test func collectionManagerErrorRendersFriendly() {
        #expect(!PageCollectionManagerError.propertyNotFound.localizedDescription.contains("PageCollectionManagerError"))
    }
}
