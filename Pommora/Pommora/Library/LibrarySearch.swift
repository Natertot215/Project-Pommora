import Foundation
import Observation

@Observable
final class LibrarySearchCache {
    private var headings: [UUID: [HeadingParser.Heading]] = [:]

    func headings(for file: FileReference) -> [HeadingParser.Heading] {
        if let cached = headings[file.id] { return cached }

        let parsed: [HeadingParser.Heading]
        if file.isMarkdown, file.existsOnDisk, let text = try? FileIO.read(file.url) {
            parsed = HeadingParser.parse(text)
        } else {
            parsed = []
        }
        headings[file.id] = parsed
        return parsed
    }
}

enum LibrarySearch {
    struct Hit: Identifiable {
        enum Kind {
            case filename
            case heading(text: String, line: Int)
        }
        let id: String
        let file: FileReference
        let kind: Kind
        let matchedRange: Range<String.Index>
    }

    struct Results {
        let filenames: [Hit]
        let headings: [Hit]
        var isEmpty: Bool { filenames.isEmpty && headings.isEmpty }
        static let empty = Results(filenames: [], headings: [])
    }

    static func run(query: String, folders: [VirtualFolder], cache: LibrarySearchCache) -> Results {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        var filenameHits: [Hit] = []
        var headingHits: [Hit] = []

        for folder in folders {
            let sortedFiles = folder.files.sorted(by: { $0.order < $1.order })
            for file in sortedFiles {
                if let range = file.titleWithoutExtension.range(of: trimmed, options: .caseInsensitive) {
                    filenameHits.append(Hit(
                        id: "\(file.id):filename",
                        file: file,
                        kind: .filename,
                        matchedRange: range
                    ))
                }
                for heading in cache.headings(for: file) {
                    if let range = heading.text.range(of: trimmed, options: .caseInsensitive) {
                        headingHits.append(Hit(
                            id: "\(file.id):h\(heading.line)",
                            file: file,
                            kind: .heading(text: heading.text, line: heading.line),
                            matchedRange: range
                        ))
                    }
                }
            }
        }

        return Results(filenames: filenameHits, headings: headingHits)
    }
}
