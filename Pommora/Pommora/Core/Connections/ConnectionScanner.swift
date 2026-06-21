import Foundation

/// Pure body scanner: extracts `[[Title]]` (Page) connections from a Markdown
/// body — `[[ ]]` is the ONLY connection syntax (PagesV2 decision #3; `{{ }}`
/// is never scanned). Title-only; a legacy `[[Name|id]]` pipe is tolerated (the
/// id segment is dropped). `![[ ]]` image embeds are excluded. Repeats to the
/// same title aggregate into `multiplicity`. No deps — runs off-actor inside
/// index write closures. The regex is `internal` (not `private`) so
/// `ConnectionRewriter` reuses it.
enum ConnectionScanner {
    nonisolated static let pageRegex = try! NSRegularExpression(
        pattern: #"(?<!!)\[\[([^\[\]\r\n|]+)(?:\|[^\]\r\n]*)?\]\]"#)

    nonisolated static func scan(body: String) -> [ScannedConnection] {
        var counts: [String: Int] = [:]
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        for m in pageRegex.matches(in: body, options: [], range: full) {
            let raw = ns.substring(with: m.range(at: 1))
            let key = ConnectionTitle.normalize(raw)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts.map { ScannedConnection(normalizedTitle: $0.key, multiplicity: $0.value) }
    }
}
