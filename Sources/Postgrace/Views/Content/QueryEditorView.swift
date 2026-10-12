import SwiftUI

/// SQL query editor with results display and history sidebar.
struct QueryEditorView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Bindable var queryViewModel: QueryViewModel
    @State private var showHistory = false
    @State private var showHelperBar = true
    @State private var executionStartTime: Date? = nil
    @State private var pendingSafetyCheck: SQLSafetyCheckResult? = nil

    @State private var pendingExecutionMode: ExecutionTargetMode = .currentOrSelected

    private enum ExecutionTargetMode {
        case currentOrSelected
        case all
    }

    var body: some View {
        HSplitView {
            // Main editor + results
            VSplitView {
                editorPane(queryText: $queryViewModel.queryText)
                resultsPane
            }

            // Query history panel (toggleable)
            if showHistory {
                QueryHistoryView()
                    .environment(queryViewModel)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
            }
        }
        .environment(queryViewModel)
        .sheet(item: $pendingSafetyCheck) { check in
            let conn = connectionViewModel.selectedConnection
            SafeModeConfirmationSheet(
                host: conn?.host ?? "localhost",
                port: conn?.port ?? 5432,
                database: conn?.database ?? "postgres",
                isLocalhost: conn?.isLocalhost ?? true,
                safetyResult: check,
                sql: queryViewModel.queryText,
                onConfirm: {
                    pendingSafetyCheck = nil
                    executeConfirmed(mode: pendingExecutionMode)
                },
                onCancel: {
                    pendingSafetyCheck = nil
                }
            )
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
                    let stmts = queryViewModel.statementSpans
                    let hasMultiple = stmts.count > 1
                    let hasSelection = !queryViewModel.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    // Execute / Run Current Button
                    Button {
                        handleExecuteRequest(mode: .currentOrSelected)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            if hasSelection {
                                Text("Run Selection (⌘↵)")
                                    .font(.system(size: 11, weight: .semibold))
                            } else if hasMultiple, let current = queryViewModel.statementAtCursor {
                                Text("Run Query #\(current.index + 1) (⌘↵)")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Text("Execute (⌘↵)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
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
                    .help(hasSelection ? "Run currently selected SQL query (⌘↵)" : (hasMultiple ? "Run query at cursor (⌘↵)" : "Execute SQL query (⌘↵)"))

                    // Run All Button (when multiple statements exist)
                    if hasMultiple {
                        Button {
                            handleExecuteRequest(mode: .all)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Run All (\(stmts.count)) (⌘⇧↵)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(PostgraceTheme.emeraldRw)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .help("Execute all \(stmts.count) statements sequentially (⌘⇧↵)")
                    }
                }

                // Safe Mode Toolbar Item (FR-2.2)
                safeModeToolbarItem

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

                // Query Helper toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showHelperBar.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showHelperBar ? "sparkles" : "sparkle")
                            .font(.system(size: 10))
                        Text("Helper")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(showHelperBar ? PostgraceTheme.accentSky : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(showHelperBar ? PostgraceTheme.accentSkyMuted : PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(showHelperBar ? PostgraceTheme.accentSky.opacity(0.4) : PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .help("Toggle SQL Query Helper Bar")

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

            // Contextual SQL Helper Bar
            if showHelperBar {
                helperBar
            }

            // Native SQL text editor with cursor tracking and line numbers
            SQLEditorView(
                text: $queryViewModel.queryText,
                selectedRange: $queryViewModel.selectedRange,
                selectedText: $queryViewModel.selectedText,
                placeholder: "Type SQL queries here (separate multiple queries with semicolons ;)...",
                tables: schemaViewModel.tables,
                columns: schemaViewModel.columns,
                schemas: schemaViewModel.schemas,
                onExecuteCurrent: {
                    handleExecuteRequest(mode: .currentOrSelected)
                },
                onExecuteAll: {
                    handleExecuteRequest(mode: .all)
                }
            )
            .background(PostgraceTheme.canvas)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 150)
    }

    // MARK: - SQL Helper Bar

    private var helperBar: some View {
        let chips = SQLAutocompleteService.contextualChips(
            for: queryViewModel.queryText,
            at: queryViewModel.selectedRange.location,
            tables: schemaViewModel.tables,
            columns: schemaViewModel.columns
        )

        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(PostgraceTheme.accentSky)
                Text("Suggest:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(chips) { chip in
                        Button {
                            insertHelperText(chip.insertText)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chip.kind.iconName)
                                    .font(.system(size: 8))
                                    .foregroundColor(helperKindColor(chip.kind))
                                Text(chip.text)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(PostgraceTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(chip.detail ?? "Insert \(chip.text)")
                    }
                }
                .padding(.vertical, 3)
            }

            Spacer(minLength: 4)

            // Tables quick insert menu
            let allTables: [TableInfo] = schemaViewModel.tables.values.flatMap { $0 }
            if !allTables.isEmpty {
                Menu {
                    Section("Database Tables") {
                        ForEach(allTables.prefix(25)) { tbl in
                            Button("\(tbl.name) (\(tbl.estimatedRowCount) rows)") {
                                insertHelperText("\(tbl.name) ")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 9))
                        Text("Tables")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            // Columns quick insert menu
            let allColumns = schemaViewModel.columns
            if !allColumns.isEmpty {
                Menu {
                    ForEach(allColumns.keys.sorted(), id: \.self) { tableKey in
                        Section(tableKey) {
                            ForEach(allColumns[tableKey] ?? []) { col in
                                Button("\(col.name) (\(col.dataType))") {
                                    insertHelperText("\(col.name) ")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "number")
                            .font(.system(size: 9))
                        Text("Columns")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            // Quick SQL clauses
            Menu {
                Button("WHERE ...") { insertHelperText("WHERE ") }
                Button("ORDER BY ... DESC") { insertHelperText("ORDER BY  DESC ") }
                Button("GROUP BY ...") { insertHelperText("GROUP BY ") }
                Button("LIMIT 100") { insertHelperText("LIMIT 100") }
                Button("INNER JOIN ... ON ...") { insertHelperText("INNER JOIN  ON ") }
                Button("LEFT JOIN ... ON ...") { insertHelperText("LEFT JOIN  ON ") }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "flowchart")
                        .font(.system(size: 9))
                    Text("Clauses")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }
            .menuStyle(.borderlessButton)
            .padding(.trailing, 8)
        }
        .frame(height: 28)
        .background(PostgraceTheme.surface.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }

    private func helperKindColor(_ kind: SQLCompletionItem.Kind) -> Color {
        switch kind {
        case .keyword: return PostgraceTheme.accentSky
        case .table: return PostgraceTheme.emeraldRw
        case .column: return .orange
        case .function: return .purple
        case .clause: return .cyan
        case .snippet: return .secondary
        }
    }

    private func insertHelperText(_ textToInsert: String) {
        let nsString = queryViewModel.queryText as NSString
        let loc = min(queryViewModel.selectedRange.location, nsString.length)
        let newText = nsString.replacingCharacters(in: NSRange(location: loc, length: 0), with: textToInsert)
        queryViewModel.queryText = newText
        queryViewModel.selectedRange = NSRange(location: loc + (textToInsert as NSString).length, length: 0)
    }

    // MARK: - Results Pane

    private var resultsPane: some View {
        VStack(spacing: 0) {
            // Multi-query result tabs (shown when multiple statements have executed)
            if queryViewModel.statementResults.count > 1 {
                statementResultTabBar
            }

            // Status bar
            statementStatusBar

            // Active Result View
            statementContentView
        }
        .frame(minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Multi-Statement Tabs & Status Bar

    private var statementResultTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(queryViewModel.statementResults) { stmtResult in
                        let isSelected = queryViewModel.selectedStatementIndex == stmtResult.index
                        Button {
                            queryViewModel.selectedStatementIndex = stmtResult.index
                        } label: {
                            HStack(spacing: 5) {
                                if stmtResult.isSuccess {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(PostgraceTheme.emeraldRw)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(PostgraceTheme.destructiveRed)
                                }

                                Text("Query #\(stmtResult.index + 1)")
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)

                                if stmtResult.isSuccess {
                                    Text(stmtResult.columnCount > 0 ? "(\(stmtResult.rowCount) rows)" : "(\(stmtResult.rowCount) aff.)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("(Error)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(PostgraceTheme.destructiveRed)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? PostgraceTheme.surfaceElevated : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(isSelected ? PostgraceTheme.accentSky.opacity(0.5) : PostgraceTheme.border.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Spacer()

            let totalTime = queryViewModel.statementResults.reduce(0.0) { $0 + $1.duration }
            Text(String(format: "%d queries • %.3fs", queryViewModel.statementResults.count, totalTime))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.trailing, 10)
        }
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }

    private var statementStatusBar: some View {
        HStack {
            if let active = queryViewModel.activeStatementResult {
                if active.isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PostgraceTheme.emeraldRw)
                        .font(.caption)
                    if active.columnCount > 0 {
                        Text("\(active.rowCount) rows")
                            .font(.caption.monospacedDigit())
                        Text("•")
                            .font(.caption)
                            .foregroundColor(PostgraceTheme.border)
                        Text("\(active.columnCount) columns")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("\(active.rowCount) rows affected")
                            .font(.caption.monospacedDigit())
                    }
                    Text("•")
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.border)
                    Text(String(format: "%.3f s", active.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.border)
                    let inlineStmt = String(active.statement.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                    Text(SQLSyntaxHighlighter.attributedString(for: inlineStmt, fontSize: 11))
                        .lineLimit(1)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                        .font(.caption)
                    Text(active.error ?? "Query failed")
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                        .lineLimit(1)
                }
            } else if let result = queryViewModel.result {
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
    }

    @ViewBuilder
    private var statementContentView: some View {
        if let active = queryViewModel.activeStatementResult {
            if let result = active.result, !result.columns.isEmpty {
                DataGridView(queryResult: result)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let error = active.error {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Text("Statement Execution Error")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text(SQLSyntaxHighlighter.attributedString(for: active.statement, fontSize: 11))
                        .padding(8)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Successful mutation or DDL statement (e.g. CREATE TABLE, INSERT 0 1)
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(PostgraceTheme.emeraldRw)
                    Text("Query Executed Successfully")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(active.rowCount) rows affected • \(String(format: "%.3f s", active.duration))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(SQLSyntaxHighlighter.attributedString(for: active.statement, fontSize: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .lineLimit(3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let result = queryViewModel.result {
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

    private func formatQuery() {
        let text = queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        queryViewModel.queryText = SQLFormatter.format(text)
    }

    // MARK: - Safe Mode & Execution Handlers

    @ViewBuilder
    private var safeModeToolbarItem: some View {
        let conn = connectionViewModel.selectedConnection
        let isLocked = conn?.isSafeModeLocked ?? false
        let isEffective = conn?.isSafeModeEffective ?? false

        if isLocked {
            // Remote: Inactive locked badge
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Safe Mode: ON (Enforced)")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(PostgraceTheme.destructiveRed)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(PostgraceTheme.destructiveRedMuted)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PostgraceTheme.destructiveRed.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
            )
            .help("Safe Mode is permanently locked for remote connections to protect against accidental changes.")
        } else if isEffective {
            // Localhost: Safe Mode ON
            Button {
                connectionViewModel.toggleSafeMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Safe Mode: ON")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(PostgraceTheme.emeraldRw)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(PostgraceTheme.emeraldRwMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PostgraceTheme.emeraldRw.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
                )
            }
            .buttonStyle(.plain)
            .help("Safe Mode is ON. Click to disable for localhost.")
        } else {
            // Localhost: Safe Mode OFF (Default)
            Button {
                connectionViewModel.toggleSafeMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shield")
                        .font(.system(size: 10))
                    Text("Safe Mode: OFF")
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
            .help("Safe Mode is OFF. Click to enable for localhost.")
        }
    }

    private func handleExecuteRequest(mode: ExecutionTargetMode = .currentOrSelected) {
        let text = queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let isSafeMode = connectionViewModel.selectedConnection?.isSafeModeEffective ?? false
        if isSafeMode {
            if mode == .all {
                let check = SQLSafetyAnalyzer.analyze(text)
                if check.isDangerous {
                    pendingSafetyCheck = check
                    pendingExecutionMode = .all
                    return
                }
            } else {
                let trimmedSelection = queryViewModel.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let sqlToCheck: String
                if !trimmedSelection.isEmpty {
                    sqlToCheck = trimmedSelection
                } else if let current = queryViewModel.statementAtCursor {
                    sqlToCheck = current.statement
                } else {
                    sqlToCheck = text
                }

                let check = SQLSafetyAnalyzer.analyze(sqlToCheck)
                if check.isDangerous {
                    pendingSafetyCheck = check
                    pendingExecutionMode = .currentOrSelected
                    return
                }
            }
        }

        executeConfirmed(mode: mode)
    }

    private func executeConfirmed(mode: ExecutionTargetMode = .currentOrSelected) {
        executionStartTime = Date()
        Task {
            if mode == .all {
                await queryViewModel.executeAll()
            } else {
                await queryViewModel.executeCurrentOrSelected()
            }
            executionStartTime = nil
        }
    }
}
