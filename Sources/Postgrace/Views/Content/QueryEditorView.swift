import SwiftUI

/// SQL query editor with results display and history sidebar.
struct QueryEditorView: View {
    @Environment(QueryViewModel.self) private var queryViewModel
    @State private var showHistory = false
    @State private var executionStartTime: Date? = nil

    @FocusState private var isEditorFocused: Bool

    var body: some View {
        @Bindable var vm = queryViewModel

        HSplitView {
            // Main editor + results
            VSplitView {
                editorPane(queryText: $vm.queryText)
                resultsPane
            }

            // Query history panel (toggleable)
            if showHistory {
                QueryHistoryView()
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
            }
        }
    }

    // MARK: - Editor Pane

    private func editorPane(queryText: Binding<String>) -> some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                if queryViewModel.isExecuting {
                    Button {
                        queryViewModel.cancelQuery()
                        executionStartTime = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Cancel (Esc)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(PostgraceTheme.destructiveRed)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Cancel / Abort running query (Esc or ⌘.)")
                } else {
                    Button {
                        executionStartTime = Date()
                        Task {
                            await queryViewModel.executeQuery()
                            executionStartTime = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Execute (⌘↵)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(PostgraceTheme.accentSky)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Format SQL Button
                Button {
                    formatQuery()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                        Text("Format")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("Format SQL Query (⌘⇧F)")

                Button {
                    queryViewModel.clearResult()
                    queryViewModel.queryText = ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)

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
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text("Templates")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)

                Spacer()

                if queryViewModel.isExecuting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        if let start = executionStartTime {
                            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                                let elapsed = timeline.date.timeIntervalSince(start)
                                Text(String(format: "Executing… (%.1fs)", elapsed))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(PostgraceTheme.accentSky)
                            }
                        } else {
                            Text("Executing…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            queryViewModel.cancelQuery()
                            executionStartTime = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(PostgraceTheme.destructiveRed)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel query")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.destructiveRed.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }

                // Query history toggle button (no native AppKit toolbar)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHistory.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showHistory ? "clock.fill" : "clock")
                            .font(.system(size: 10))
                        Text("History")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(showHistory ? PostgraceTheme.accentSky : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(showHistory ? PostgraceTheme.accentSkyMuted : PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(showHistory ? PostgraceTheme.accentSky.opacity(0.4) : PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .help("Toggle Query History")
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

            // SQL text editor with tap-to-focus and placeholder
            ZStack(alignment: .topLeading) {
                TextEditor(text: queryText)
                    .font(.system(.body, design: .monospaced))
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .background(PostgraceTheme.canvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)

                if queryViewModel.queryText.isEmpty {
                    Text("Type a SQL query here (e.g. SELECT * FROM ...) or choose a Template above...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(NSColor.placeholderTextColor))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isEditorFocused = true
            }
            .onAppear {
                isEditorFocused = true
            }
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
                        .foregroundColor(PostgraceTheme.emeraldRw)
                        .font(.caption)
                    Text("\(result.rows.count) rows")
                        .font(.caption.monospacedDigit())
                    Text("•")
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.border)
                    Text("\(result.columns.count) columns")
                        .font(.caption.monospacedDigit())
                    Text("•")
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.border)
                    Text(String(format: "%.3f s", result.executionTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                } else if let error = queryViewModel.executionError {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
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
            .background(PostgraceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .top
            )

            // Result grid
            if let result = queryViewModel.result {
                DataGridView(queryResult: result)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func formatQuery() {
        let text = queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        queryViewModel.queryText = SQLFormatter.format(text)
    }
}
