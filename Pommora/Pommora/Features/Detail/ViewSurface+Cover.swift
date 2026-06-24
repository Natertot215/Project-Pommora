import SwiftUI

extension ViewSurface {
    @ViewBuilder
    var coverPickerHost: some View {
        if let item = coverTarget, let nexus = nexusManager.currentNexus {
            CoverPicker(
                page: item.page, pageCollection: item.parent.pageCollection,
                collection: item.parent.collection, set: item.parent.set,
                nexus: nexus, isPresenting: $isPickingCover)
        }
    }

    /// Cover-area context menu (gallery) — Set / Change / Remove Cover.
    @ViewBuilder
    func coverMenuItems(for item: ViewItem) -> some View {
        let hasCover = item.page.frontmatter.cover != nil
        Button(hasCover ? "Change Cover" : "Set Cover") {
            coverTarget = item
            isPickingCover = true
        }
        if hasCover {
            Button("Remove Cover", role: .destructive) { removeCover(item) }
        }
    }

    private func removeCover(_ item: ViewItem) {
        let previousCover = item.page.frontmatter.cover
        var fm = item.page.frontmatter
        fm.cover = nil
        Task {
            do {
                try await contentManager.updatePageFrontmatter(
                    item.page, frontmatter: fm, pageCollection: item.parent.pageCollection,
                    collection: item.parent.collection, set: item.parent.set)
                // Delete the cleared cover file ONLY AFTER the `cover = nil`
                // write succeeds, so a failed write never leaves `cover`
                // pointing at a deleted file.
                if let nexus = nexusManager.currentNexus {
                    CoverAssetStore().delete(relativePath: previousCover, for: item.page.id, in: nexus)
                }
            } catch {}
        }
    }
}
