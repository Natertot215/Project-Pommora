import Foundation

enum HeadingParser {
    struct Heading: Hashable {
        let text: String
        let line: Int
    }

    static func parse(_ markdown: String) -> [Heading] {
        var headings: [Heading] = []
        var inFencedCode = false

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFencedCode.toggle()
                continue
            }
            guard !inFencedCode else { continue }

            guard let firstNonHash = trimmed.firstIndex(where: { $0 != "#" }) else { continue }
            let hashCount = trimmed.distance(from: trimmed.startIndex, to: firstNonHash)
            guard (1...6).contains(hashCount) else { continue }
            guard trimmed[firstNonHash] == " " else { continue }

            let text = trimmed[trimmed.index(after: firstNonHash)...]
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            headings.append(Heading(text: text, line: index + 1))
        }
        return headings
    }
}
