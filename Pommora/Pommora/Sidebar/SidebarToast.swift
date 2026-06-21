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
/// fire from user-driven actions yet): AgendaTaskManager, AgendaEventManager,
/// TierConfigManager. Add them if user-reachable code paths appear later.
struct SidebarToast: View {
    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SavedConfigManager.self) private var savedConfigManager
    @Environment(SidebarSectionsManager.self) private var sidebarSectionsManager
    @Environment(HomepageManager.self) private var homepageManager

    @State private var displayedError: (any Error)? = nil
    @State private var displayedSource: ErrorSource? = nil

    enum ErrorSource: String, Hashable {
        case area, topic, project, vault, content, savedConfig, sidebarSections, homepage
    }

    var body: some View {
        Group {
            if let err = displayedError {
                HStack(spacing: PUI.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(friendlyMessage(err))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, PUI.Spacing.lg)
                .padding(.vertical, PUI.Spacing.sm)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PUI.Radius.card))
                .padding(.horizontal, PUI.Spacing.md)
                .padding(.vertical, PUI.Spacing.xs)
            }
        }
        .onChange(of: errorChangeID(areaManager.pendingError)) { _, _ in
            capture(from: areaManager.pendingError, source: .area)
        }
        .onChange(of: errorChangeID(topicManager.pendingError)) { _, _ in
            capture(from: topicManager.pendingError, source: .topic)
        }
        .onChange(of: errorChangeID(projectManager.pendingError)) { _, _ in
            capture(from: projectManager.pendingError, source: .project)
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
        .onChange(of: errorChangeID(sidebarSectionsManager.pendingError)) { _, _ in
            capture(from: sidebarSectionsManager.pendingError, source: .sidebarSections)
        }
        .onChange(of: errorChangeID(homepageManager.pendingError)) { _, _ in
            capture(from: homepageManager.pendingError, source: .homepage)
        }
    }

    private func capture(from err: (any Error)?, source: ErrorSource) {
        guard let err else { return }
        displayedError = err
        displayedSource = source
    }

    private func dismiss() {
        switch displayedSource {
        case .area: areaManager.pendingError = nil
        case .topic: topicManager.pendingError = nil
        case .project: projectManager.pendingError = nil
        case .vault: vaultManager.pendingError = nil
        case .content: contentManager.pendingError = nil
        case .savedConfig: savedConfigManager.pendingError = nil
        case .sidebarSections: sidebarSectionsManager.pendingError = nil
        case .homepage: homepageManager.pendingError = nil
        case .none: break
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
