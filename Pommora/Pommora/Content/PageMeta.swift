import Foundation

/// Lightweight in-app tracking value for `.md` Page files in a Collection.
/// Carries enough to enforce uniqueness, validation, and listing without
/// loading body content. ContentManager (Task 39) is the first real consumer;
/// shape is locked here to unblock PageValidator (Task 33).
///
/// Not Codable — purely in-memory; the file's frontmatter + filename are the
/// on-disk truth.
struct PageMeta: Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var title: String  // derived from filename (no extension)
    var url: URL  // .md file location
    var frontmatter: PageFrontmatter
}
