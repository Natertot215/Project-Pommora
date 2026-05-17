//
//  IconPickerField.swift
//  Pommora
//
//  Reusable button-field used inside the Create sheets to pick an SF Symbol.
//  Wraps SymbolPicker directly (not IconPickerSheet) because Create flows hold
//  the picked symbol in local `@State` until Save — they have no manager to
//  route through. IconPickerSheet still owns the "Change Icon" flow on
//  existing rows, where the picked symbol must be persisted via the right
//  manager.
//

import SwiftUI
import SymbolPicker

/// A button that displays the currently-picked SF Symbol (or a placeholder)
/// and opens the SymbolPicker as a nested sheet on tap.
struct IconPickerField: View {
    @Binding var symbol: String?
    var placeholder: String = "questionmark.circle"

    @State private var pickerOpen: Bool = false

    var body: some View {
        Button {
            pickerOpen = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol ?? placeholder)
                    .frame(width: 20, height: 20)
                Text(symbol ?? "Choose Icon")
                    .foregroundStyle(symbol == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $pickerOpen) {
            SymbolPicker(symbol: $symbol)
        }
    }
}
