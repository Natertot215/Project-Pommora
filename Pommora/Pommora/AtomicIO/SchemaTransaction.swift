import Foundation

/// Errors thrown by `SchemaTransaction`. Surface to managers via the existing
/// pendingError toast pipeline (per Pommora discipline).
enum SchemaTransactionError: Error, Sendable {
    /// A staged temp-file write failed during phase 1 (stage). The first URL is the
    /// target whose temp write blew up; the wrapped error is the underlying cause.
    case stageFailed(target: URL, underlying: any Error)
    /// A rename from temp → target failed during phase 2 (commit). Already-renamed
    /// targets have been rolled back to their backups; remaining temps were deleted.
    case commitFailed(target: URL, underlying: any Error)
}

/// Atomic multi-file commit primitive for schema mutations that touch >1 file.
///
/// Used by schema mutations that touch >1 file: schema type-change with
/// value-drop (writes schema sidecar + every affected member file), ID-rekey
/// migration (writes schema + every member file per Type), and move-strip
/// (writes source + destination member files).
///
/// ## Pattern (two-phase commit)
///
/// 1. **Stage:** every `stage(payload:to:)` records a (payload, target, temp)
///    triple. `commit()` writes all payloads to sibling `<target>.txn-<ulid>`
///    temp files. If ANY stage write fails, every already-written temp is
///    deleted and `SchemaTransactionError.stageFailed` is thrown.
/// 2. **Commit:** every staged temp is moved over its target via
///    `FileManager.moveItem`. Pre-existing targets are first moved aside to a
///    sibling `<target>.bak-<ulid>` backup. If ANY rename fails, the backups
///    are restored over their targets (best-effort) and remaining temps are
///    deleted; `SchemaTransactionError.commitFailed` is thrown. On success,
///    backups are deleted.
///
/// ## Idempotence
///
/// Before staging, every target's parent directory is swept for stale
/// `*.txn-*` and `*.bak-*` siblings (likely left over from a previous
/// crashed commit). They are deleted unconditionally — they have no value
/// across processes.
///
/// ## Single-file commits
///
/// Use `AtomicJSON.write` directly for single-file commits. `SchemaTransaction`
/// is overhead-only when the mutation is one file.
final class SchemaTransaction {

    private struct StagedWrite {
        let payload: Data
        let target: URL
        let temp: URL
    }

    private var pending: [StagedWrite] = []

    init() {}

    /// Stage a payload to be written to `url` on the next `commit()`. Multiple
    /// stages to the same target overwrite each other (last-stage-wins) — not
    /// generally useful but defined.
    func stage(payload: Data, to url: URL) {
        let temp = url.appendingPathExtension("txn-\(ULID.generate())")
        pending.append(StagedWrite(payload: payload, target: url, temp: temp))
    }

    /// Convenience: encode + stage in one call for any `Codable` value using
    /// the same JSON encoding shape as `AtomicJSON.write`.
    func stage<T: Codable>(_ value: T, to url: URL) throws {
        stage(payload: try AtomicJSON.encode(value), to: url)
    }

    /// Two-phase commit. Throws if any stage or rename fails; on throw, the
    /// filesystem is restored to its pre-commit state (best-effort).
    func commit() throws {
        cleanStaleTemps()

        // Phase 1: stage all temps.
        var stagedTemps: [URL] = []
        for write in pending {
            do {
                try write.payload.write(to: write.temp, options: [.atomic])
                stagedTemps.append(write.temp)
            } catch {
                // Roll back already-staged temps.
                for url in stagedTemps {
                    try? FileManager.default.removeItem(at: url)
                }
                throw SchemaTransactionError.stageFailed(target: write.target, underlying: error)
            }
        }

        // Phase 2: rename all temps to targets in deterministic order.
        var renamed: [(target: URL, backup: URL?)] = []
        for write in pending {
            do {
                var backup: URL?
                if FileManager.default.fileExists(atPath: write.target.path) {
                    let backupURL = write.target.appendingPathExtension("bak-\(ULID.generate())")
                    try FileManager.default.moveItem(at: write.target, to: backupURL)
                    backup = backupURL
                }
                try FileManager.default.moveItem(at: write.temp, to: write.target)
                renamed.append((write.target, backup))
            } catch {
                // Rollback: restore backups (reverse order so nested updates restore correctly),
                // delete any remaining temps.
                for (target, backup) in renamed.reversed() {
                    try? FileManager.default.removeItem(at: target)
                    if let backup {
                        try? FileManager.default.moveItem(at: backup, to: target)
                    }
                }
                // Also restore the backup we'd just moved aside (before the move failure),
                // since `renamed` doesn't include this iteration.
                if FileManager.default.fileExists(atPath: write.temp.path) {
                    try? FileManager.default.removeItem(at: write.temp)
                }
                // Any further pending temps haven't been touched yet; they get cleaned next call.
                throw SchemaTransactionError.commitFailed(target: write.target, underlying: error)
            }
        }

        // Phase 3: success — delete backups.
        for (_, backup) in renamed {
            if let backup {
                try? FileManager.default.removeItem(at: backup)
            }
        }

        // Clear pending so a transaction object can be reused (not common, but
        // doesn't cost anything).
        pending.removeAll()
    }

    /// Sweep every staged target's parent directory for `*.txn-*` and `*.bak-*`
    /// siblings left over from a previous crashed commit and delete them.
    private func cleanStaleTemps() {
        let parentDirs = Set(pending.map { $0.target.deletingLastPathComponent() })
        let txnMarker = ".txn-"
        let bakMarker = ".bak-"
        for dir in parentDirs {
            guard
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for entry in contents {
                let name = entry.lastPathComponent
                if name.contains(txnMarker) || name.contains(bakMarker) {
                    try? FileManager.default.removeItem(at: entry)
                }
            }
        }
    }
}
