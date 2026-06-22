import Foundation
import UniformTypeIdentifiers

/// Handles copying files into an entity's attachment folder inside the nexus.
///
/// Attachment layout: `<nexus>/.nexus/attachments/<entity-id>/<filename>`
/// The `FileRef.path` returned is **relative** to the nexus root (POSIX forward
/// slashes) so it survives nexus moves — per Pommora's "files survive a stack
/// rebuild" constraint.
struct AttachmentManager: Sendable {

    // MARK: - Errors

    enum AttachmentError: Error, Equatable {
        /// The source file does not exist at the given URL.
        case sourceNotFound
        /// File is between 50 MB and 500 MB and `requireConfirmation == true`.
        /// Caller must show a confirmation UI then re-call with `requireConfirmation: false`.
        case sizeWarningRequired(sizeBytes: Int)
        /// File is at or above 500 MB — hard cap, never allowed.
        case exceedsSizeCap(sizeBytes: Int)
        /// The detected MIME type is not in the caller-supplied `accept` list.
        case mimeNotAccepted(mime: String, accept: [String])
        /// `FileManager.copyItem` failed; the associated string is the error description.
        case copyFailed(String)
    }

    // MARK: - Constants

    enum Constants {
        /// Files above this threshold require caller confirmation (50 MB).
        static let warningSizeBytes: Int = 50_000_000
        /// Files at or above this threshold are always rejected (500 MB).
        static let hardCapBytes: Int = 500_000_000
    }

    // MARK: - Attach

    /// Copies `source` into `<nexus>/.nexus/attachments/<entityID>/` and returns
    /// a `FileRef` whose `path` is relative to the nexus root.
    func attach(
        file source: URL,
        to entityID: String,
        nexusRoot: URL,
        accept: [String]? = nil,
        requireConfirmation: Bool = true
    ) async throws -> FileRef {
        let fm = FileManager.default

        guard fm.fileExists(atPath: source.path) else {
            throw AttachmentError.sourceNotFound
        }

        let attrs = try fm.attributesOfItem(atPath: source.path)
        let sizeBytes = (attrs[.size] as? Int) ?? 0

        if sizeBytes >= Constants.hardCapBytes {
            throw AttachmentError.exceedsSizeCap(sizeBytes: sizeBytes)
        }

        if sizeBytes > Constants.warningSizeBytes, requireConfirmation {
            throw AttachmentError.sizeWarningRequired(sizeBytes: sizeBytes)
        }

        let detectedMIME = mimeType(for: source)
        if let accept {
            guard mimeIsAccepted(detectedMIME, in: accept) else {
                throw AttachmentError.mimeNotAccepted(mime: detectedMIME, accept: accept)
            }
        }

        let destDir = NexusPaths.attachmentsDir(for: entityID, in: nexusRoot)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let originalName = source.lastPathComponent
        let finalName = Filesystem.collisionSafeName(originalName, in: destDir, fm: fm)
        let destURL = destDir.appendingPathComponent(finalName, isDirectory: false)

        do {
            try fm.copyItem(at: source, to: destURL)
        } catch {
            throw AttachmentError.copyFailed(error.localizedDescription)
        }

        // nexus-relative path uses POSIX forward slashes so it survives a nexus move.
        let relativePath = ".nexus/attachments/\(entityID)/\(finalName)"

        return FileRef(
            path: relativePath,
            originalName: originalName,
            addedAt: Date(),
            mimeType: detectedMIME
        )
    }

    // MARK: - Private helpers

    /// Derives the preferred MIME type from the source URL's file extension.
    /// Falls back to `"application/octet-stream"` when UTType lookup fails.
    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty,
              let utType = UTType(filenameExtension: ext),
              let mime = utType.preferredMIMEType
        else {
            return "application/octet-stream"
        }
        return mime
    }

    /// Returns `true` when `mime` matches at least one pattern in `accept`.
    /// Exact match: `"application/pdf"` matches only `"application/pdf"`.
    /// Wildcard: `"image/*"` matches any MIME that starts with `"image/"`.
    private func mimeIsAccepted(_ mime: String, in accept: [String]) -> Bool {
        for pattern in accept {
            if pattern == mime {
                return true
            }
            if pattern.hasSuffix("/*") {
                let prefix = String(pattern.dropLast(2)) + "/"
                if mime.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }

}
