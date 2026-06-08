import Testing

@testable import Pommora

/// T5.3 — the template editor's cover-eligible filter: only `.file` properties
/// whose `accept` admits an image MIME qualify.
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
}
