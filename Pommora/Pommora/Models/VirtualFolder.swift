import Foundation
import SwiftData

@Model
final class VirtualFolder {
    var id: UUID
    var name: String
    var createdAt: Date
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \FileReference.folder)
    var files: [FileReference] = []

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.order = order
    }
}
