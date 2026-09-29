import SwiftUI

/// SQL query editor with results display and history sidebar.
struct QueryEditorView: View {
    @Environment(QueryViewModel.self) private var queryViewModel
    @State private var showHistory = false

    var body: some View {
        HSplitView {
            // Main editor + results
            VSplitView {
                editorPane
                resultsPane
            }

            // Query history panel (toggleable)
            if showHistory {
                QueryHistoryView()
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        showHistory.toggle()
                    }
                } label: {
                    Image(systemName: showHistory ? "clock.fill" : "clock")
                }
                .help("Toggle Query History")
            }
        }
    }

    // MARK: - Editor Pane

    private var editorPane: some View {
        @Bindable var queryVM = queryViewModel
        return VStack(spacing: 0) {
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
                    Label("Clear", systemImage: "trash")
                }

                Divider()
                    .frame(height: 16)

                // Quick templates
                Menu {
                    Button("SELECT * FROM ...") {
                        queryViewModel.queryText = "SELECT * FROM  LIMIT 100;"
                    }
                    Button("EXPLAIN ANALYZE ...") {
                        queryViewModel.queryText = "EXPLAIN ANALYZE "
                    }
                    Button("Show running queries") {
                        queryViewModel.queryText = """
                        SELECT pid, now() - pg_stat_activity.query_start AS duration,
                               query, state
                        FROM pg_stat_activity
                        WHERE (now() - pg_stat_activity.query_start) > interval '0 seconds'
                        AND state != 'idle'
                        ORDER BY duration DESC;
                        """
                    }
                    Button("Table sizes") {
                        queryViewModel.queryText = """
                        SELECT schemaname, tablename,
                               pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
                               pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size
                        FROM pg_tables
                        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
                        ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
                        """
                    }
                } label: {
                    Label("Templates", systemImage: "doc.text")
                }
                .controlSize(.small)

                Spacer()

                if queryViewModel.isExecuting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Executing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            // SQL text editor
            TextEditor(text: $queryVM.queryText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .frame(minHeight: 150)
    }

    // MARK: - Results Pane

    private var resultsPane: some View {
        VStack(spacing: 0) {
            // Status bar
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
                    Text("\(result.columns.count) columns")
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
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Ready — ⌘↵ to execute")
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
