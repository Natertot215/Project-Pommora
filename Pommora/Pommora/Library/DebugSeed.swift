#if DEBUG
import Foundation
import SwiftData

enum DebugSeed {
    @MainActor
    static func run(context: ModelContext) {
        let folderDescriptor = FetchDescriptor<VirtualFolder>()
        let fileDescriptor = FetchDescriptor<FileReference>()
        let existingFolders = (try? context.fetch(folderDescriptor)) ?? []
        let existingFiles = (try? context.fetch(fileDescriptor)) ?? []
        guard existingFolders.isEmpty && existingFiles.isEmpty else { return }

        let tmp = FileManager.default.temporaryDirectory

        let samples: [(folder: String, fileBase: String, ext: String, content: String)] = [
            ("Notes", "Q3 forecast notes", "md", """
            # Q3 forecast notes

            ## Revenue projections

            Notes about Q3 revenue.

            ## Risks

            Some risks to call out.
            """),
            ("Notes", "Meeting prep", "md", """
            # Meeting prep

            ## Agenda

            - Discuss Q3 forecast
            - Review project alpha

            ## Notes
            """),
            ("Drafts", "Project alpha overview", "md", """
            # Project alpha overview

            Project alpha is the next big initiative.

            ## Goals

            ## Timeline
            """),
            ("Drafts", "Random thoughts", "txt", "Just some random text without headings."),
        ]

        var foldersByName: [String: VirtualFolder] = [:]
        for (index, sample) in samples.enumerated() {
            let folder: VirtualFolder
            if let existing = foldersByName[sample.folder] {
                folder = existing
            } else {
                folder = VirtualFolder(name: sample.folder, order: foldersByName.count)
                context.insert(folder)
                foldersByName[sample.folder] = folder
            }

            let filename = "\(sample.fileBase).\(sample.ext)"
            let url = tmp.appending(path: filename)
            try? sample.content.data(using: .utf8)?.write(to: url, options: .atomic)

            let ref = FileReference(
                path: url.path(percentEncoded: false),
                displayName: filename,
                order: index
            )
            ref.folder = folder
            context.insert(ref)
        }
    }
}
#endif
