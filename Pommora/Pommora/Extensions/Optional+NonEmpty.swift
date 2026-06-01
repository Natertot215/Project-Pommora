import Foundation

extension Optional where Wrapped == String {
    /// The wrapped string when present and non-empty; `nil` otherwise.
    /// Normalizes the "empty string means unset" convention shared by optional
    /// `icon` / `title` fields, so call sites don't repeat
    /// `(x?.isEmpty == false) ? x : nil`.
    var nonEmpty: String? { (self?.isEmpty == false) ? self : nil }
}
