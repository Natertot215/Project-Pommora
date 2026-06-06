import Foundation

/// Pure title-rewrite over a body. Replaces every `[[oldTitle]]` / `{{oldTitle}}`
/// (case-insensitive normalized match; legacy `[[old|id]]` tolerated → id dropped)
/// with newTitle, touching only the matching syntax. Reuses ConnectionScanner regexes.
enum ConnectionRewriter {
    static func rewrite(body: String, oldTitle: String, newTitle: String, syntax: ConnectionSyntax) -> String {
        let oldKey = ConnectionTitle.normalize(oldTitle)
        let (open, close) = syntax == .page ? ("[[", "]]") : ("{{", "}}")
        let regex = syntax == .page ? ConnectionScanner.pageRegex : ConnectionScanner.itemRegex
        let ns = body as NSString
        let result = NSMutableString(string: body)
        for m in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).reversed() {
            let title = ns.substring(with: m.range(at: 1))
            guard ConnectionTitle.normalize(title) == oldKey else { continue }
            result.replaceCharacters(in: m.range, with: "\(open)\(newTitle)\(close)")
        }
        return result as String
    }
}

/// Rewrites every body that links a renamed target. Atomic via SchemaTransaction;
/// the caller reverts the target's own file-rename if `run` throws. Returns the
/// touched sources so the caller can reconcile their connection rows.
struct ConnectionCascade {
    let rootURL: URL
    let indexQuery: IndexQuery

    struct Touched: Sendable {
        let id: String
        let kind: EntityKind
        let title: String
        let newBody: String
    }

    func run(targetID: String, oldTitle: String, newTitle: String,
             targetSyntax: ConnectionSyntax) async throws -> [Touched] {
        let inbound = try await indexQuery.incomingConnections(targetID: targetID)
        guard !inbound.isEmpty else { return [] }
        let txn = SchemaTransaction()
        var touched: [Touched] = []
        for edge in inbound {
            guard
                let container = try await indexQuery.entityContainer(id: edge.sourceID, kind: edge.sourceKind),
                let url = ConnectionFileLocator.locate(id: edge.sourceID, kind: edge.sourceKind, container: container, nexusRoot: rootURL)
            else { continue }
            let fileData: Data
            let title: String
            let newBody: String
            switch edge.sourceKind {
            case .page:
                let pf = try PageFile.load(from: url)
                newBody = ConnectionRewriter.rewrite(body: pf.body, oldTitle: oldTitle, newTitle: newTitle, syntax: targetSyntax)
                fileData = try AtomicYAMLMarkdown.encode(frontmatter: pf.frontmatter, body: newBody, preservingFrom: url, modeledKeys: PageFrontmatter.modeledKeys)
                title = pf.title
            case .item:
                let it = try Item.load(from: url)
                newBody = ConnectionRewriter.rewrite(body: it.description, oldTitle: oldTitle, newTitle: newTitle, syntax: targetSyntax)
                fileData = try AtomicYAMLMarkdown.encode(frontmatter: it.frontmatter, body: newBody, preservingFrom: url, modeledKeys: ItemFrontmatter.modeledKeys)
                title = it.title
            default:
                continue
            }
            txn.stage(payload: fileData, to: url)
            touched.append(Touched(id: edge.sourceID, kind: edge.sourceKind, title: title, newBody: newBody))
        }
        try txn.commit()   // throws → caller reverts the rename; index untouched
        return touched
    }
}
