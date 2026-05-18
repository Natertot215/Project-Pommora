import Foundation

/// Composite of frontmatter + body for a `.md` Page file.
/// I/O via `AtomicYAMLMarkdown`. Title derived from filename on load.
struct PageFile: Equatable, Sendable {
    var frontmatter: PageFrontmatter
    var body: String
    var title: String  // derived from filename on load; not persisted

    init(frontmatter: PageFrontmatter, body: String, title: String = "") {
        self.frontmatter = frontmatter
        self.body = body
        self.title = title
    }

    static func load(from url: URL) throws -> PageFile {
        let (fm, body): (PageFrontmatter, String) =
            try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: url)
        return PageFile(
            frontmatter: fm,
            body: body,
            title: url.deletingPathExtension().lastPathComponent
        )
    }

    func save(to url: URL) throws {
        try AtomicYAMLMarkdown.write(frontmatter: frontmatter, body: body, to: url)
    }
}
