// MARK: - Components convention
//
// Each file in this directory is a verified reference implementation of one
// SwiftUI primitive category. Rules:
//
//   1. Every component example MUST be cited against the macOS 26 swiftinterface
//      with a comment of the form: `// swiftinterface: <line>: <signature>`
//   2. Every example MUST have a corresponding `#Preview` block.
//   3. Every example MUST use semantic primitives only — no `.frame(width:)`,
//      `.font(.system(size:))`, hex colors, or hand-tuned paddings.
//      See L-001 in `.claude/lessons.md`.
//   4. Every category in this directory MUST have a corresponding section
//      in `.claude/components-reference.md`.
//
// To add a category: create a new `*Components.swift` file here, add a row to
// `.claude/framework.md` Component categories table, add a section to
// `.claude/components-reference.md`.

import SwiftUI

private struct ComponentsConvention {}
