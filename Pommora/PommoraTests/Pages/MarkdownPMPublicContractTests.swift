import AppKit
import Foundation
import MarkdownPM
import SwiftUI
import Testing

/// Locks the MarkdownPM public surface the rebuild must not silently break:
/// the editor init's app-used params, the surviving dormant seams, the
/// TextInsets public init, the public free functions, and the two frozen
/// attribute-key string literals.
@MainActor
@Suite("MarkdownPMPublicContract")
struct MarkdownPMPublicContractTests {

    @Test("MarkdownPMEditor constructs with only the app-used args")
    func editorConstructsWithAppArgs() {
        // The app passes text, configuration, fontName, fontSize, documentId,
        // isEditable, foldedHeadings, onScrollOffsetChange. All other params
        // default. This compiling IS the contract.
        var text = "# hi"
        var folded: Set<String> = []
        _ = MarkdownPMEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            foldedHeadings: Binding(get: { folded }, set: { folded = $0 }),
            configuration: .default,
            fontName: "SF Pro Text",
            fontSize: 15,
            documentId: "page-1",
            isEditable: true,
            onScrollOffsetChange: { _ in }
        )
    }

    @Test("Dormant wikilink + inline seams survive (isWikiLinkActive, pendingInlineReplacement, onInlineSelectionChange, onPasteImage)")
    func dormantSeamsSurvive() {
        var text = ""
        var active = false
        var pending: InlineReplacementRequest? = nil
        // Passing all four dormant seams must still compile after the rebuild.
        _ = MarkdownPMEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            isWikiLinkActive: Binding(get: { active }, set: { active = $0 }),
            pendingInlineReplacement: Binding(get: { pending }, set: { pending = $0 }),
            onPasteImage: { _ in nil },
            onInlineSelectionChange: { _ in }
        )
    }

    @Test("TextInsets public init(horizontal:vertical:) is callable")
    func textInsetsPublicInit() {
        let insets = TextInsets(horizontal: 12, vertical: 8)
        #expect(insets.horizontal == 12)
        #expect(insets.vertical == 8)
    }

    @Test("MarkdownPlainText.extract(from:) strips markdown to plain prose")
    func plainTextExtract() {
        let plain = MarkdownPlainText.extract(from: "# Title\n\n**bold** text")
        #expect(plain.contains("Title"))
        #expect(plain.contains("bold"))
        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
    }

    @Test("reconcileFoldedHeadings is public and drops orphans")
    func reconcilePublic() {
        let kept = MarkdownDetection.reconcileFoldedHeadings(
            ["## A", "## Gone"], in: "## A\nx\n")
        #expect(kept == ["## A"])
    }

    @Test("Frozen attribute-key string literals are EXACT (NodeLinkID / TaskCheckbox)")
    func frozenAttributeKeyLiterals() {
        // The Swift symbol `.wikiLinkID` maps to the literal "NodeLinkID"
        // (divergent on purpose — do NOT rename the literal). renderer +
        // makeStorageState read these by raw string.
        #expect(NSAttributedString.Key.wikiLinkID == NSAttributedString.Key("NodeLinkID"))
        #expect(NSAttributedString.Key.taskCheckbox == NSAttributedString.Key("TaskCheckbox"))
    }
}
