import SwiftUI

struct SidebarView: View {
    @Binding var searchText: String

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                Section(section.title) {
                    EmptyView()
                }
            }
        }
        .controlSize(.regular)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .searchable(text: $searchText, placement: .sidebar)
    }
}

#Preview {
    @Previewable @State var query = ""
    return SidebarView(searchText: $query)
}
