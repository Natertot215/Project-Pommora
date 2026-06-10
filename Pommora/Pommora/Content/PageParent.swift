import Foundation

/// Where a Page lives inside a Page Type. The spec allows Content to sit
/// directly in a Page Type's root folder OR inside a PageCollection sub-folder; this
/// enum lets sidebar rows and sheets route create/rename/delete calls to the
/// correct ContentManager overload without leaking that branching into UI code.
enum PageParent: Hashable {
    case collection(PageCollection, vault: PageType)
    case vaultRoot(PageType)
}
