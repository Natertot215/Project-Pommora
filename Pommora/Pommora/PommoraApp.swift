import SwiftUI
import SwiftData

@main
struct PommoraApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            VirtualFolder.self,
            FileReference.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}
