import Foundation

/// Per-property render variant for the Status property type.
///
/// Surfaced via `PropertyDefinition.displayAs` (optional). nil = type
/// default, which for Status is `.box`. Other property types **ignore**
/// this field entirely — it's explicitly NOT a generic per-property
/// presentation knob.
///
/// Cases:
///   - `.box` — colored dot/circle + label (default for Status).
///   - `.select` — colored chip with label (same shape as Select-property render).
///   - `.chip` — icon-only chip. v0.3.1.x uses `PropertyChip.chip(icon:)` with
///     a hardcoded `"square.dashed"` placeholder. Final per-group/per-option
///     icons + the `Settings.statusGroupIcons` configuration land in a
///     pre-v1 cleanup phase (tracked in Prospects.md).
enum DisplayVariant: String, Codable, Equatable, Sendable {
    case box
    case select
    case chip
}
