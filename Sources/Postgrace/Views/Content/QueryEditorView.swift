import SwiftUI

/// SQL query editor with results display.
struct QueryEditorView: View {
    @Environment(QueryViewModel.self) private var queryViewModel

    var body: some View {
        @Bindable var queryVM = queryViewModel

        VSplitView {
            // Editor pane
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button {
                        Task {
                            await queryViewModel.executeQuery()
                        }
                    } label: {
                        Label("Execute", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(queryViewModel.isExecuting || queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        queryViewModel.clearResult()
                        queryViewModel.queryText = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }

                    Spacer()

                    if queryViewModel.isExecuting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // SQL text editor
                TextEditor(text: $queryVM.queryText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minHeight: 150)

            // Results pane
            VStack(spacing: 0) {
                // Status bar between editor and results
                HStack {
                    if let result = queryViewModel.result {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("\(result.rows.count) rows")
                            .font(.caption)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.3f s", result.executionTime))
                            .font(.caption)
                    } else if let error = queryViewModel.executionError {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    } else {
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))

                // Result grid
                if let result = queryViewModel.result {
                    DataGridView(queryResult: result)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Execute a query to see results")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(minHeight: 150)
        }
    }
}
