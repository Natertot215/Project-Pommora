import Foundation

/// A container sidecar that persists a Page display order and loads from a
/// metadata URL. Lets `PageContentManager.loadAll` re-read the canonical
/// `page_order` from ANY container kind through one helper, instead of repeating
/// the `(try? <Type>.load(...))?.pageOrder ?? fallback` block per type.
protocol PageOrderSidecar {
    var pageOrder: [String]? { get }
    static func load(from metadataURL: URL) throws -> Self
}

extension PageCollection: PageOrderSidecar {}
extension PageSet: PageOrderSidecar {}
extension PageType: PageOrderSidecar {}
