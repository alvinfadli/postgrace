import SwiftUI

/// Quick filter bar positioned directly atop the DataGridView matching the artifact.
/// Features a dark monospace input, cyan "WHERE" badge, and pagination controls.
struct QuickFilterBarView: View {
    @Environment(DataGridViewModel.self) private var dataGridViewModel
    @Binding var filterClause: String
    let onApply: () -> Void

    private var paginationText: String {
        let startRow: Int64 = Int64(dataGridViewModel.currentPage * dataGridViewModel.pageSize + 1)
        let endRow: Int64 = min(startRow + Int64(dataGridViewModel.pageSize) - 1, dataGridViewModel.totalRows)
        return "\(startRow) – \(endRow) of \(dataGridViewModel.totalRows) rows"
    }

    var body: some View {
        HStack(spacing: 8) {
            // "FILTER:" Label
            Text("FILTER:")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))

            // Filter Expression Input Box (WHERE badge + text input)
            HStack(spacing: 6) {
                Text("WHERE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PostgraceTheme.accentSky)
                    .padding(.leading, 4)

                TextField("e.g. status = 'active' AND id > 100", text: $filterClause)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(.primary)
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
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: 420)
            .background(PostgraceTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )

            // Apply Button
            Button {
                onApply()
            } label: {
                Text("Apply")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(PostgraceTheme.accentSky)
                    .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            // Pagination Controls
            if dataGridViewModel.totalRows > 0 {
                Text(paginationText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    Button {
                        Task { await dataGridViewModel.previousPage() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(dataGridViewModel.hasPreviousPage ? .primary : .secondary.opacity(0.4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!dataGridViewModel.hasPreviousPage)

                    Button {
                        Task { await dataGridViewModel.nextPage() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(dataGridViewModel.hasNextPage ? .primary : .secondary.opacity(0.4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!dataGridViewModel.hasNextPage)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }
}
