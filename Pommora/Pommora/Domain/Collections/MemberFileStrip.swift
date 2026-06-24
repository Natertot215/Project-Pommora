//
//  MemberFileStrip.swift
//  Pommora
//
//  Resilient iteration for member-file property strips. Schema mutations
//  (delete-property, change-type) rewrite every member file of a Type to drop a
//  property's value. A hand-authored member that can't be decoded — e.g. a
//  frontmatter-less `.md` (no `id`, so `PageFrontmatter` decode throws
//  `keyNotFound(.id)`) or a corrupt `.json` — must NOT abort the whole mutation.
//  A file we can't read can't be carrying the property value, so skipping it is
//  lossless (the canonical schema-sidecar strip is staged separately).
//
//  This is the SINGLE source of that guard, shared by the `PageCollectionManager`
//  delete-property + change-type loops. The per-Type load / strip /
//  encode stays inline at each call site (it genuinely differs — YAML+`PageFrontmatter`
//  vs JSON+`AgendaTask`/`AgendaEvent`); only the resilient iteration is hoisted.
//

import Foundation
import os

enum MemberFileStrip {
    private nonisolated static let log = Logger(subsystem: "Pommora", category: "MemberFileStrip")

    /// Runs `strip` for each member file, skipping (and logging) any file whose
    /// `strip` throws. `strip` should load the file, drop the property value, and
    /// stage the rewrite; use `return` (not `continue`) to skip a file that doesn't
    /// carry the property.
    nonisolated static func forEach(_ files: [URL], _ strip: (URL) throws -> Void) {
        for url in files {
            do {
                try strip(url)
            } catch {
                log.error(
                    "Skipping unreadable member file \(url.lastPathComponent, privacy: .public) during property strip: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
