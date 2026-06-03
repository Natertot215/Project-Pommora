// swift-tools-version: 5.9
import PackageDescription

// MarkdownPM — Pommora's owned Markdown editor engine (the v3 rebuild
// target). Originally vendored from nodes-app/swift-markdown-engine
// (Apache 2.0, upstream SHA e683a62); now Pommora-owned and maintained
// in-tree. Built as a local Swift Package — NOT as raw source files in
// Pommora's main target — because:
//
//  1. The package targets Swift 5.9. Pommora is Swift 6 + strict
//     concurrency + ExistentialAny. The package boundary lets MarkdownPM
//     keep its own concurrency contract while Pommora's app code stays
//     Swift-6-strict.
//  2. MarkdownPM internals (MarkdownPMStyler, MarkdownTokenizer) are
//     module-internal types; the app consumes only the public front door.
//  3. Apple's swift-markdown supplies the GFM AST.
//
// See NOTICE.md for the upstream attribution + per-file modification log.

let package = Package(
    name: "MarkdownPM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownPM", targets: ["MarkdownPM"])
    ],
    dependencies: [
        // Apple's swift-markdown supplies the GFM AST that drives the new
        // Pommora-side tokenizer + styler implementations. Pinned to 0.8.0
        // exact to match Pommora's Package.resolved.
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0")
    ],
    targets: [
        .target(
            name: "MarkdownPM",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(name: "MarkdownPMTests", dependencies: ["MarkdownPM"])
    ]
)
