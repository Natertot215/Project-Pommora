import Foundation

/// Page-side template config (reserved parity with ItemTemplateConfig — restores
/// the symmetric-code HARD RULE). All optional, null-round-trip. `layout` is
/// reserved (Pages have no archetype yet); `openIn` is inert until PreviewWindow.
struct PageTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: LayoutArchetype?   // reserved — Pages have no archetype yet
    var defaultBody: String?
    var openIn: OpenInMode?         // inert until PreviewWindow

    init(layout: LayoutArchetype? = nil, defaultBody: String? = nil, openIn: OpenInMode? = nil) {
        self.layout = layout; self.defaultBody = defaultBody; self.openIn = openIn
    }
    enum CodingKeys: String, CodingKey {
        case layout
        case defaultBody = "default_body"
        case openIn = "open_in"
    }
}
