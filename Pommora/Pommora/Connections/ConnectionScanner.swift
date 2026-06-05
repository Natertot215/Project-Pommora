import Foundation

/// Pure body scanner: extracts `[[Title]]` (Page) and `{{Title}}` (Item)
/// connections from a Markdown body. Title-only; a legacy `[[Name|id]]` pipe is
/// tolerated (the id segment is dropped). `![[ ]]` image embeds are excluded.
/// Repeats to the same (syntax, title) aggregate into `multiplicity`. No deps —
/// runs off-actor inside index write closures. Regexes are `internal` (not
/// `private`) so `ConnectionRewriter` reuses them.
enum ConnectionScanner {
    nonisolated static let pageRegex = try! NSRegularExpression(
        pattern: #"(?<!!)\[\[([^\[\]\r\n|]+)(?:\|[^\]\r\n]*)?\]\]"#)
    nonisolated static let itemRegex = try! NSRegularExpression(
        pattern: #"\{\{([^{}\r\n|]+)(?:\|[^}\r\n]*)?\}\}"#)

    nonisolated static func scan(body: String) -> [ScannedConnection] {
        var counts: [ConnectionSyntax: [String: Int]] = [.page: [:], .item: [:]]
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        func collect(_ regex: NSRegularExpression, _ syntax: ConnectionSyntax) {
            for m in regex.matches(in: body, options: [], range: full) {
                let raw = ns.substring(with: m.range(at: 1))
                let key = ConnectionTitle.normalize(raw)
                guard !key.isEmpty else { continue }
                counts[syntax, default: [:]][key, default: 0] += 1
            }
        }
        collect(pageRegex, .page)
        collect(itemRegex, .item)
        return counts.flatMap { syntax, m in
            m.map { ScannedConnection(normalizedTitle: $0.key, syntax: syntax, multiplicity: $0.value) }
        }
    }
}
