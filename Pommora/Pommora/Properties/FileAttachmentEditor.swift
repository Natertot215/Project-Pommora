import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileAttachmentEditorViewModel

/// View-model holding attach/remove logic so it can be tested without driving SwiftUI.
@Observable
@MainActor
final class FileAttachmentEditorViewModel {
    var attachments: [FileRef]
    var sizeWarningPending: SizeWarningState?
    var errorMessage: String?

    let entityID: String
    let nexusRoot: URL
    let accept: [String]?
    let onChange: ([FileRef]) -> Void

    private let manager = AttachmentManager()

    struct SizeWarningState {
        let sourceURL: URL
        let sizeBytes: Int
        var formattedSize: String {
            let mb = Double(sizeBytes) / 1_000_000.0
            return String(format: "%.1f MB", mb)
        }
    }

    init(
        attachments: [FileRef],
        entityID: String,
        nexusRoot: URL,
        accept: [String]?,
        onChange: @escaping ([FileRef]) -> Void
    ) {
        self.attachments = attachments
        self.entityID = entityID
        self.nexusRoot = nexusRoot
        self.accept = accept
        self.onChange = onChange
    }

    // MARK: - Attach

    func attach(file source: URL, requireConfirmation: Bool = true) async {
        do {
            let ref = try await manager.attach(
                file: source,
                to: entityID,
                nexusRoot: nexusRoot,
                accept: accept,
                requireConfirmation: requireConfirmation
            )
            attachments.append(ref)
            onChange(attachments)
        } catch AttachmentManager.AttachmentError.sizeWarningRequired(let sizeBytes) {
            sizeWarningPending = SizeWarningState(sourceURL: source, sizeBytes: sizeBytes)
        } catch AttachmentManager.AttachmentError.exceedsSizeCap(let sizeBytes) {
            let mb = Double(sizeBytes) / 1_000_000.0
            errorMessage = String(format: "File is too large (%.0f MB). The maximum size is 500 MB.", mb)
        } catch AttachmentManager.AttachmentError.mimeNotAccepted(let mime, _) {
            errorMessage = "File type \"\(mime)\" is not accepted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmSizeWarning() async {
        guard let pending = sizeWarningPending else { return }
        sizeWarningPending = nil
        await attach(file: pending.sourceURL, requireConfirmation: false)
    }

    func dismissSizeWarning() {
        sizeWarningPending = nil
    }

    // MARK: - Remove

    func remove(at offsets: IndexSet) {
        attachments.remove(atOffsets: offsets)
        onChange(attachments)
    }

    func remove(ref: FileRef) {
        attachments.removeAll { $0.path == ref.path }
        onChange(attachments)
    }
}

// MARK: - FileAttachmentEditor

/// Drop zone + thumbnail strip for `.file` property values.
///
/// Handles the size-warning confirmation flow inline so callers don't need to
/// manage `AttachmentManager.AttachmentError` themselves.
struct FileAttachmentEditor: View {
    @Binding var attachments: [FileRef]
    let entityID: String
    let nexusRoot: URL
    let accept: [String]?
    let onChange: ([FileRef]) -> Void

    @State private var vm: FileAttachmentEditorViewModel?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            dropZone
            if let model = vm, !model.attachments.isEmpty {
                thumbnailStrip(model: model)
            }
        }
        .onAppear { initVM() }
        .alert(
            "Attach Large File?",
            isPresented: Binding(
                get: { vm?.sizeWarningPending != nil },
                set: { if !$0 { vm?.dismissSizeWarning() } }
            ),
            presenting: vm?.sizeWarningPending
        ) { pending in
            Button("Attach Anyway") {
                Task { await vm?.confirmSizeWarning() }
            }
            Button("Cancel", role: .cancel) { vm?.dismissSizeWarning() }
        } message: { pending in
            Text("This file is \(pending.formattedSize). Attach anyway?")
        }
        .alert(
            "Attachment Error",
            isPresented: Binding(
                get: { vm?.errorMessage != nil },
                set: { if !$0 { vm?.errorMessage = nil } }
            )
        ) {
            Button("OK") { vm?.errorMessage = nil }
        } message: {
            Text(vm?.errorMessage ?? "")
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PUI.Radius.field)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                )
                .background(
                    RoundedRectangle(cornerRadius: PUI.Radius.field)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.08)
                              : Color(.windowBackgroundColor).opacity(0.3))
                )
            HStack(spacing: PUI.Spacing.sm) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text("Drop files here or")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button("Choose…") { openPanel() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            .padding(PUI.Spacing.xl)
        }
        .frame(height: 60)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Thumbnail strip

    private func thumbnailStrip(model: FileAttachmentEditorViewModel) -> some View {
        FileAttachmentThumbnailStrip(
            attachments: model.attachments,
            onRemove: { ref in model.remove(ref: ref) }
        )
    }

    // MARK: - Private helpers

    private func initVM() {
        if vm == nil {
            let model = FileAttachmentEditorViewModel(
                attachments: attachments,
                entityID: entityID,
                nexusRoot: nexusRoot,
                accept: accept,
                onChange: { refs in
                    attachments = refs
                    onChange(refs)
                }
            )
            vm = model
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await vm?.attach(file: url)
                }
            }
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let accept {
            panel.allowedContentTypes = accept.compactMap { mime -> UTType? in
                if mime.hasSuffix("/*") {
                    let prefix = String(mime.dropLast(2))
                    return UTType(mimeType: prefix)
                }
                return UTType(mimeType: mime)
            }
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            Task { await vm?.attach(file: url) }
        }
    }
}

// MARK: - FileAttachmentThumbnailStrip (isolated sub-view)

/// Isolated sub-view for the attachment list. Receives plain value types to avoid
/// GRDB `SQLSpecificExpressible` overload conflicts inside ForEach closures.
private struct FileAttachmentThumbnailStrip: View {
    let attachments: [FileRef]
    let onRemove: (FileRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            ForEach(attachments, id: \.path) { ref in
                FileAttachmentThumbnailRow(ref: ref, onRemove: onRemove)
            }
        }
    }
}

// MARK: - FileAttachmentThumbnailRow

private struct FileAttachmentThumbnailRow: View {
    let ref: FileRef
    let onRemove: (FileRef) -> Void

    var body: some View {
        HStack(spacing: PUI.Spacing.sm) {
            Image(systemName: iconName(for: ref.mimeType))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(ref.originalName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                onRemove(ref)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.vertical, PUI.Spacing.xxs)
        .padding(.horizontal, PUI.Spacing.xs)
    }

    private func iconName(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}
