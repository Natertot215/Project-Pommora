import SwiftUI

/// Transient error banner that observes the user-reachable managers'
/// `pendingError` properties. Shows the most recent error from any manager;
/// the user dismisses by tapping the X.
///
/// Rendered at the top of the sidebar List (inside `SidebarView.body`) so the
/// toast doesn't break the load-bearing Section / SectionHeader layout — the
/// List body itself never changes.
///
/// **Excluded** observers (no UI surface in v0.2 — their `pendingError` can't
/// fire from user-driven actions yet): AgendaManager, HomepageManager,
/// TierConfigManager. Add them if user-reachable code paths appear later.
struct SidebarToast: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(ContentManager.self) private var contentManager
    @Environment(SavedConfigManager.self) private var savedConfigManager

    @State private var displayedError: (any Error)? = nil
    @State private var displayedSource: ErrorSource? = nil

    enum ErrorSource: String, Hashable {
        case space, topic, vault, content, savedConfig
    }

    var body: some View {
        Group {
            if let err = displayedError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(friendlyMessage(err))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .onChange(of: errorChangeID(spaceManager.pendingError)) { _, _ in
            capture(from: spaceManager.pendingError, source: .space)
        }
        .onChange(of: errorChangeID(topicManager.pendingError)) { _, _ in
            capture(from: topicManager.pendingError, source: .topic)
        }
        .onChange(of: errorChangeID(vaultManager.pendingError)) { _, _ in
            capture(from: vaultManager.pendingError, source: .vault)
        }
        .onChange(of: errorChangeID(contentManager.pendingError)) { _, _ in
            capture(from: contentManager.pendingError, source: .content)
        }
        .onChange(of: errorChangeID(savedConfigManager.pendingError)) { _, _ in
            capture(from: savedConfigManager.pendingError, source: .savedConfig)
        }
    }

    private func capture(from err: (any Error)?, source: ErrorSource) {
        guard let err else { return }
        displayedError = err
        displayedSource = source
    }

    private func dismiss() {
        switch displayedSource {
        case .space:       spaceManager.pendingError = nil
        case .topic:       topicManager.pendingError = nil
        case .vault:       vaultManager.pendingError = nil
        case .content:     contentManager.pendingError = nil
        case .savedConfig: savedConfigManager.pendingError = nil
        case .none:        break
        }
        displayedError = nil
        displayedSource = nil
    }

    private func friendlyMessage(_ err: any Error) -> String {
        if let localized = (err as? (any LocalizedError))?.errorDescription { return localized }
        return err.localizedDescription
    }

    /// Produce a hashable change-trigger from an optional any Error so `.onChange`
    /// can detect when pendingError is reassigned. Uses the error's localized
    /// description as a proxy for identity; if errors with the same message fire
    /// twice in a row the toast won't re-display — acceptable trade-off for v0.2.
    private func errorChangeID(_ err: (any Error)?) -> String {
        err.map { ($0 as? (any LocalizedError))?.errorDescription ?? $0.localizedDescription } ?? ""
    }
}
