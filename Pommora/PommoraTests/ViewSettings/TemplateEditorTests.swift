import Testing

@testable import Pommora

/// T5.3 — the template editor's pure parts: the cover-eligible filter (only
/// `.file` properties whose `accept` admits an image MIME qualify) and the
/// display-write helper (setting one promoted property's `display` updates that
/// entry by id and preserves the others). The embedded `ItemWindowRenderer`
/// edit-mode surface (pin/unpin + drag-reorder) is build-verified, not
/// unit-tested — it's exercised by ItemWindowRenderer's own tests.
@Suite("Template editor")
struct TemplateEditorTests {

    // MARK: - Cover-eligible filter

    private func def(
        _ id: String, type: PropertyType, accept: [String]? = nil
    ) -> PropertyDefinition {
        PropertyDefinition(id: id, name: id, type: type, accept: accept)
    }

    @Test("coverEligible keeps only .file defs whose accept admits an image type")
    func coverEligibleFiltersToImageFiles() {
        let defs = [
            def("img", type: .file, accept: ["image/*"]),
            def("png", type: .file, accept: ["image/png"]),
            def("pdf", type: .file, accept: ["application/pdf"]),
            def("anyFile", type: .file, accept: nil),
            def("text", type: .url, accept: ["image/*"]),  // not .file → excluded
        ]
        let eligible = ItemTemplatePane.coverEligible(defs).map(\.id)
        #expect(eligible == ["img", "png"])
    }

    @Test("isCoverEligible: image wildcard and concrete image MIME pass; non-image fail")
    func isCoverEligiblePerType() {
        #expect(ItemTemplatePane.isCoverEligible(def("a", type: .file, accept: ["image/*"])))
        #expect(ItemTemplatePane.isCoverEligible(def("b", type: .file, accept: ["image/jpeg"])))
        #expect(!ItemTemplatePane.isCoverEligible(def("c", type: .file, accept: ["application/pdf"])))
        #expect(!ItemTemplatePane.isCoverEligible(def("d", type: .file, accept: nil)))
        #expect(!ItemTemplatePane.isCoverEligible(def("e", type: .file, accept: [])))
        // A non-file property never qualifies, even with an image accept-list.
        #expect(!ItemTemplatePane.isCoverEligible(def("f", type: .relation, accept: ["image/*"])))
    }

    @Test("coverEligible preserves input order and excludes everything non-eligible")
    func coverEligibleEmptyAndOrder() {
        #expect(ItemTemplatePane.coverEligible([]).isEmpty)
        let defs = [
            def("z", type: .file, accept: ["image/png"]),
            def("a", type: .file, accept: ["image/*"]),
        ]
        #expect(ItemTemplatePane.coverEligible(defs).map(\.id) == ["z", "a"])
    }

    // MARK: - Display-write helper

    @Test("applyDisplay updates the matching promoted entry by id and preserves others")
    func applyDisplayUpdatesById() {
        let promoted = [
            PromotedProperty(id: "p1", display: .inline),
            PromotedProperty(id: "p2", display: nil),
            PromotedProperty(id: "p3", display: .chips),
        ]
        let result = ItemTemplatePane.applyDisplay(.banner, to: "p2", in: promoted)
        #expect(result.map(\.id) == ["p1", "p2", "p3"])  // order preserved
        #expect(result[0].display == .inline)  // untouched
        #expect(result[1].display == .banner)  // updated
        #expect(result[2].display == .chips)  // untouched
    }

    @Test("applyDisplay can clear an override (nil display) on the target only")
    func applyDisplayCanClear() {
        let promoted = [
            PromotedProperty(id: "p1", display: .banner),
            PromotedProperty(id: "p2", display: .chips),
        ]
        let result = ItemTemplatePane.applyDisplay(nil, to: "p1", in: promoted)
        #expect(result[0].display == nil)
        #expect(result[1].display == .chips)
    }

    @Test("applyDisplay no-ops when the id isn't present")
    func applyDisplayUnknownId() {
        let promoted = [PromotedProperty(id: "p1", display: .inline)]
        let result = ItemTemplatePane.applyDisplay(.banner, to: "missing", in: promoted)
        #expect(result == promoted)
    }
}
