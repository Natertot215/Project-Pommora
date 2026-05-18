import Foundation

/// Where a Page or Item lives inside a Vault. The spec allows Content to sit
/// directly in a Vault's root folder OR inside a Collection sub-folder; this
/// enum lets sidebar rows and sheets route create/rename/delete calls to the
/// correct ContentManager overload without leaking that branching into UI code.
enum PageParent: Hashable {
    case collection(Pommora.Collection, vault: Vault)
    case vaultRoot(Vault)
}
