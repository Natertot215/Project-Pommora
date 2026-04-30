import SwiftUI

private struct DemoItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private let demoItems: [DemoItem] = [
    .init(title: "Alpha", subtitle: "First entry"),
    .init(title: "Beta", subtitle: "Second entry"),
    .init(title: "Gamma", subtitle: "Third entry")
]

// MARK: - List + ForEach + Section
// swiftinterface (SwiftUI): 6456: public struct List<SelectionValue, Content> : SwiftUICore.View where SelectionValue : Swift.Hashable, Content : SwiftUICore.View
// swiftinterface (SwiftUICore): 16946: public struct ForEach<Data, ID, Content> where Data : Swift.RandomAccessCollection, ID : Swift.Hashable
// swiftinterface (SwiftUI): 11007: public struct Section<Parent, Content, Footer>
struct ListExample: View {
    @State private var selection: DemoItem.ID?
    var body: some View {
        List(selection: $selection) {
            Section("Group A") {
                ForEach(demoItems) { item in
                    Label(item.title, systemImage: "circle")
                        .tag(item.id)
                }
            }
        }
        .controlSize(.regular)
    }
}

// MARK: - Table
// swiftinterface (SwiftUI): 1119: public struct Table<Value, Rows, Columns> : SwiftUICore.View where Value == Rows.TableRowValue, Rows : SwiftUI.TableRowContent, Columns : SwiftUI.TableColumnContent, Rows.TableRowValue == Columns.TableRowValue
struct TableExample: View {
    var body: some View {
        Table(demoItems) {
            TableColumn("Title", value: \.title)
            TableColumn("Subtitle", value: \.subtitle)
        }
    }
}

#Preview("List") { ListExample().frame(width: 240, height: 220) }
#Preview("Table") { TableExample().frame(width: 360, height: 220) }
