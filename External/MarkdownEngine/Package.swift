// swift-tools-version: 5.9
import PackageDescription

// Pommora vendoring of nodes-app/swift-markdown-engine (Apache 2.0,
// upstream SHA e683a62). Vendored as a local Swift Package — NOT as raw
// source files in Pommora's main target — because:
//
//  1. The engine targets Swift 5.9. Pommora is Swift 6 + strict concurrency
//     + ExistentialAny. The package boundary lets the engine use its own
//     concurrency contract while Pommora's app code stays Swift-6-strict.
//  2. Engine internals (MarkdownStyler, MarkdownTokenizer) are package-
//     internal types. Pommora's Phase-3 styler swap will inject a
//     PommoraMarkdownStyler via a service protocol added to the engine's
//     Services/, rather than by replacing symbols directly.
//  3. Selectively vendored: only the core target. The upstream's
//     `MarkdownEngineCodeBlocks` (HighlighterSwift bridge) and
//     `MarkdownEngineLatex` (SwiftMath bridge) are NOT vendored; their
//     no-op defaults in `Services/MarkdownEditorServices.swift` are
//     sufficient for v0.2.7. Bridges may be added as a later patch.
//
// See NOTICE.md for the full per-file modification log.

let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"])
    ],
    dependencies: [
        // Apple's swift-markdown supplies the GFM AST that drives the new
        // Pommora-side tokenizer + styler implementations. Pinned to 0.8.0
        // exact to match Pommora's Package.resolved.
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0")
    ],
    targets: [
        .target(
            name: "MarkdownEngine",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"])
    ]
)
