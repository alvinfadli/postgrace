import SwiftUI

/// Excel/Sequel Ace-style quick filter bar positioned directly atop the DataGridView.
struct QuickFilterBarView: View {
    @Environment(DataGridViewModel.self) private var dataGridViewModel
    @Binding var filterClause: String
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("FILTER:")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            // Filter expression input
            HStack {
                Text("WHERE")
                    .font(.caption.monospaced())
                    .foregroundColor(.accentColor)
                    .padding(.leading, 6)

                TextField("e.g. status = 'active' AND id > 100", text: $filterClause)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        onApply()
                    }

                if !filterClause.isEmpty {
                    Button {
                        filterClause = ""
                        onApply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            Button("Apply") {
                onApply()
            }
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()

            // Pagination Controls
            if dataGridViewModel.totalRows > 0 {
                Text("\(dataGridViewModel.totalRows) rows")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Button {
                        Task { await dataGridViewModel.previousPage() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!dataGridViewModel.hasPreviousPage)

                    Text("\(dataGridViewModel.currentPage + 1) / \(dataGridViewModel.totalPages)")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 44)

                    Button {
                        Task { await dataGridViewModel.nextPage() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!dataGridViewModel.hasNextPage)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
}
