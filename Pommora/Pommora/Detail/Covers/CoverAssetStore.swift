import Foundation

/// Copies a chosen image file into an entity's assets folder inside the nexus
/// and returns the nexus-relative POSIX path to store in `cover` / `banner`.
///
/// Asset layout: `<nexus>/.nexus/assets/<entity-id>/<filename>`
/// The returned path is **relative** to the nexus root (POSIX forward slashes)
/// so it survives nexus moves — per Pommora's "files survive a stack rebuild"
/// constraint. Generalizes `AttachmentManager`'s copy / collision logic; the
/// cover flow has no MIME accept-list and no soft-warn tier — just a hard cap.
struct CoverAssetStore: Sendable {

    // MARK: - Errors

    enum CoverAssetError: Error, Equatable {
        /// The source file does not exist at the given URL.
        case sourceNotFound
        /// File is at or above 500 MB — hard cap, never allowed.
        case exceedsSizeCap(sizeBytes: Int)
        /// `FileManager.copyItem` failed; the string is the error description.
        case copyFailed(String)
    }

    // MARK: - Constants

    enum Constants {
        /// Files at or above this threshold are always rejected (500 MB).
        static let hardCapBytes: Int = 500_000_000
    }

    // MARK: - Store

    /// Copies `source` into `<nexus>/.nexus/assets/<entityID>/` and returns the
    /// nexus-relative path (`.nexus/assets/<entityID>/<finalName>`).
    ///
    /// **Steps (in order):**
    /// 1. Verify source exists.
    /// 2. Read file size; hard-cap check (≥ 500 MB → throw `.exceedsSizeCap`).
    /// 3. Create destination directory if absent.
    /// 4. Collision-safe filename (suffix `-2`, `-3`, … preserving extension).
    /// 5. Copy file.
    /// 6. Return the nexus-relative path string.
    func store(image source: URL, for entityID: String, in nexus: Nexus) async throws -> String {
        let fm = FileManager.default

        // 1. Source must exist.
        guard fm.fileExists(atPath: source.path) else {
            throw CoverAssetError.sourceNotFound
        }

        // 2. Hard cap.
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let sizeBytes = (attrs[.size] as? Int) ?? 0
        if sizeBytes >= Constants.hardCapBytes {
            throw CoverAssetError.exceedsSizeCap(sizeBytes: sizeBytes)
        }

        // 3. Destination directory.
        let destDir = NexusPaths.assetsDir(for: entityID, in: nexus)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // 4. Collision-safe filename.
        let finalName = Self.collisionSafeName(source.lastPathComponent, in: destDir, fm: fm)
        let destURL = destDir.appendingPathComponent(finalName, isDirectory: false)

        // 5. Copy.
        do {
            try fm.copyItem(at: source, to: destURL)
        } catch {
            throw CoverAssetError.copyFailed(error.localizedDescription)
        }

        // 6. Nexus-relative POSIX path.
        return ".nexus/assets/\(entityID)/\(finalName)"
    }

    // MARK: - Private helpers

    /// Returns a filename that doesn't collide with existing files in `dir`.
    /// If `originalName` already exists, tries `<stem>-2.<ext>`, `<stem>-3.<ext>`, etc.
    private static func collisionSafeName(_ originalName: String, in dir: URL, fm: FileManager) -> String {
        let candidate = dir.appendingPathComponent(originalName, isDirectory: false)
        guard fm.fileExists(atPath: candidate.path) else { return originalName }

        let url = URL(fileURLWithPath: originalName)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent

        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            let attempt = dir.appendingPathComponent(name, isDirectory: false)
            if !fm.fileExists(atPath: attempt.path) {
                return name
            }
            counter += 1
        }
    }
}
