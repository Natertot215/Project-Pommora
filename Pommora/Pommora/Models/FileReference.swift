import Foundation
import SwiftData

@Model
final class FileReference {
    var id: UUID
    var lastKnownPath: String
    var displayName: String
    var addedAt: Date
    var order: Int
    var lastOpenedAt: Date?
    var folder: VirtualFolder?

    init(path: String, displayName: String, order: Int) {
        self.id = UUID()
        self.lastKnownPath = path
        self.displayName = displayName
        self.addedAt = .now
        self.order = order
        self.lastOpenedAt = nil
    }

    var url: URL {
        URL(fileURLWithPath: lastKnownPath)
    }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: lastKnownPath)
    }

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var titleWithoutExtension: String {
        (displayName as NSString).deletingPathExtension
    }

    var formatBadge: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown": return "MD"
        case "txt": return "TXT"
        default: return ext.uppercased()
        }
    }
}
