import SwiftUI

/// Custom precision sidebar showing schemas, tables, and views for the active connection.
/// Designed to match the artifact exactly (without native AppKit List chrome).
struct SidebarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @Environment(QueryViewModel.self) private var queryViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel

    @State private var searchText = ""
    @State private var expandedSchemas: Set<String> = ["public"]
    @State private var schemaForNewTable: String?

    var body: some View {
        VStack(spacing: 0) {
            // 1. FILTER TABLES QUICK INPUT
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption2)
                TextField("Filter tables…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.primary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(PostgraceTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 2. QUICK ACCESS: DATABASES & SCHEMAS CATALOGS
            HStack(spacing: 6) {
                Button {
                    tabViewModel.openDatabasesTab()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(PostgraceTheme.accentSky)
                            .font(.system(size: 10, weight: .semibold))
                        Text("Databases")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    tabViewModel.openSchemasTab()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.3.layers.3d")
                            .foregroundColor(PostgraceTheme.accentSky)
                            .font(.system(size: 10, weight: .semibold))
                        Text("Schemas")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            // 3. SCHEMAS & RELATIONS SCROLLABLE TREE
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    
                    // Category Eyebrow & Expand/Collapse controls
                    HStack {
                        Text("SCHEMAS & RELATIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

                        Spacer()

                        Button {
                            expandedSchemas = Set(schemaViewModel.schemas.map(\.name))
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Expand All Schemas")

                        Button {
                            expandedSchemas.removeAll()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Collapse All Schemas")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    if schemaViewModel.isLoading && schemaViewModel.schemas.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading schemas…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    ForEach(schemaViewModel.schemas) { schema in
                        schemaNodeView(schema)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 3.5 SELECTED TABLE METADATA SECTION BOX
            selectedTableMetadataBox

            // 4. SIDEBAR FOOTER
            HStack {
                Button {
                    Task {
                        await schemaViewModel.refresh()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Refresh")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh Schemas & Tables")

                Spacer()

                Button {
                    tabViewModel.openQueryTab()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("Query (⌘T)")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(PostgraceTheme.accentSky)
                }
                .buttonStyle(.plain)
                .help("Open New Query Tab (⌘T)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PostgraceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity)
        .background(PostgraceTheme.surface)
        .sheet(item: Binding(
            get: { schemaForNewTable.map { IdentifiableString(value: $0) } },
            set: { schemaForNewTable = $0?.value }
        )) { item in
            CreateTableSheet(initialSchema: item.value)
        }
    }

    // MARK: - Schema Node

    @ViewBuilder
    private func schemaNodeView(_ schema: SchemaInfo) -> some View {
        let isExpanded = expandedSchemas.contains(schema.name)
        let allTables = schemaViewModel.tables[schema.name] ?? []
        let filteredTables = searchText.isEmpty
            ? allTables
            : allTables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        VStack(alignment: .leading, spacing: 1) {
            // Schema Header Row
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)

                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundColor(PostgraceTheme.accentSky)

                Text(schema.name)
                    .font(.caption.bold())
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedSchemas.remove(schema.name)
                    } else {
                        expandedSchemas.insert(schema.name)
                    }
                }
                if !isExpanded && schemaViewModel.tables[schema.name] == nil {
                    Task {
                        await schemaViewModel.loadTables(for: schema.name)
                    }
                }
            }
            .contextMenu {
                Button("Browse Tables Catalog") {
                    tabViewModel.openTablesTab(schema: schema.name)
                }
                Button("New Table in '\(schema.name)'…") {
                    schemaForNewTable = schema.name
                }
                Divider()
                Button("Export Schema '\(schema.name)'…") {
                    exportViewModel.startSchemaExport(schema: schema.name)
                }
                Divider()
                Button("Manage All Schemas") {
                    tabViewModel.openSchemasTab()
                }
            }

            // Children Tables / Views
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    if schemaViewModel.tables[schema.name] == nil {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading tables…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 24)
                        .padding(.vertical, 4)
                    } else if filteredTables.isEmpty && !allTables.isEmpty {
                        Text("No matching tables")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 24)
                            .padding(.vertical, 2)
                    } else if allTables.isEmpty {
                        Text("No tables in schema")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(filteredTables) { table in
                            tableRow(schema: schema, table: table)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .task(id: "\(connectionViewModel.selectedConnection?.database ?? "")_\(schema.name)") {
            if schemaViewModel.tables[schema.name] == nil {
                await schemaViewModel.loadTables(for: schema.name)
            }
        }
    }

    // MARK: - Table Row (Matching Artifact with Active Accent Indicator)

    @ViewBuilder
    private func tableRow(schema: SchemaInfo, table: TableInfo) -> some View {
        let isActive: Bool = {
            if let activeTab = tabViewModel.activeTab,
               case .table(let tabSchema, let tabTable) = activeTab.type {
                return tabSchema == schema.name && tabTable == table.name
            }
            return false
        }()

        SidebarTableRowView(
            schema: schema,
            table: table,
            isActive: isActive,
            onSelect: {
                schemaViewModel.selectedSchema = schema
                schemaViewModel.selectedTable = table
                tabViewModel.openTableTab(schema: schema.name, table: table.name)
                Task {
                    if schemaViewModel.columns["\(schema.name).\(table.name)"] == nil {
                        await schemaViewModel.loadColumns(for: schema.name, table: table.name)
                    }
                    if schemaViewModel.tableDetails[schema.name] == nil {
                        await schemaViewModel.loadTableDetails(for: schema.name)
                    }
                    await schemaViewModel.loadAccurateRowCount(schema: schema.name, table: table.name)
                }
            },
            onOpenData: {
                schemaViewModel.selectedSchema = schema
                schemaViewModel.selectedTable = table
                tabViewModel.openTableTab(schema: schema.name, table: table.name)
                Task {
                    await schemaViewModel.loadAccurateRowCount(schema: schema.name, table: table.name)
                }
            },
            onOpenStructure: {
                schemaViewModel.selectedSchema = schema
                schemaViewModel.selectedTable = table
                tabViewModel.openStructureTab(schema: schema.name, table: table.name)
                Task {
                    await schemaViewModel.loadAccurateRowCount(schema: schema.name, table: table.name)
                }
            },
            onQueryInEditor: {
                queryViewModel.queryText = "SELECT * FROM \"\(schema.name)\".\"\(table.name)\" LIMIT 100;"
                tabViewModel.openQueryTab()
            }
        )
    }

    private func iconForTableType(_ type: TableType) -> String {
        switch type {
        case .table: return "tablecells"
        case .view: return "eye"
        case .materializedView: return "eye.fill"
        case .foreignTable: return "link"
        }
    }

    private func colorForTableType(_ type: TableType, isActive: Bool) -> Color {
        if isActive { return PostgraceTheme.accentSky }
        switch type {
        case .table: return .secondary
        case .view: return PostgraceTheme.purpleSuper
        case .materializedView: return PostgraceTheme.purpleSuper
        case .foreignTable: return PostgraceTheme.amberRo
        }
    }

    // MARK: - Selected Table Metadata Section Box

    @ViewBuilder
    private var selectedTableMetadataBox: some View {
        if let table = schemaViewModel.selectedTable {
            let detail = schemaViewModel.tableDetails[table.schema]?.first(where: { $0.name == table.name })
            let cols = schemaViewModel.columns["\(table.schema).\(table.name)"]

            VStack(alignment: .leading, spacing: 6) {
                // Section Header / Eyebrow
                HStack {
                    Text("TABLE METADATA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(table.schema)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(PostgraceTheme.accentSky)
                }

                // Table Title Row
                HStack(spacing: 5) {
                    Image(systemName: iconForTableType(table.tableType))
                        .font(.system(size: 11))
                        .foregroundColor(PostgraceTheme.accentSky)

                    Text(table.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(table.tableType == .table ? "TABLE" : table.tableType.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(PostgraceTheme.accentSkyMuted)
                        .foregroundColor(PostgraceTheme.accentSky)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Divider()
                    .background(PostgraceTheme.border)

                // Key/Value Metric Pairs
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Rows")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if schemaViewModel.isLoadingRowCount["\(table.schema).\(table.name)"] == true {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            let rc = schemaViewModel.accurateRowCount(for: table)
                            Text(rc >= 0 ? "\(rc)" : "0")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)

                            Button {
                                Task {
                                    await schemaViewModel.loadAccurateRowCount(schema: table.schema, table: table.name, forceRefresh: true)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Recalculate live accurate row count")
                        }
                    }

                    metadataRow(label: "Disk Size", value: detail?.totalSize ?? "—")
                    if let idxSize = detail?.indexSize, idxSize != "—" && idxSize != "0 bytes" {
                        metadataRow(label: "Index Size", value: idxSize)
                    }
                    metadataRow(
                        label: "Columns",
                        value: {
                            let colCount = detail?.columnCount ?? cols?.count ?? 0
                            return colCount > 0 ? "\(colCount) cols" : "—"
                        }()
                    )
                    if let pk = cols?.first(where: { $0.isPrimaryKey })?.name {
                        metadataRow(label: "Primary Key", value: pk, isAccent: true)
                    }
                }
            }
            .padding(10)
            .background(PostgraceTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .task(id: "\(table.schema).\(table.name)") {
                await schemaViewModel.loadAccurateRowCount(schema: table.schema, table: table.name)
            }
        }
    }

    private func metadataRow(label: String, value: String, isAccent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: isAccent ? .semibold : .regular, design: .monospaced))
                .foregroundColor(isAccent ? PostgraceTheme.accentSky : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Decoupled Table Row View (Localized Hover State)

struct SidebarTableRowView: View {
    let schema: SchemaInfo
    let table: TableInfo
    let isActive: Bool
    let onSelect: () -> Void
    let onOpenData: () -> Void
    let onOpenStructure: () -> Void
    let onQueryInEditor: () -> Void

    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForTableType(table.tableType))
                .font(.caption2)
                .foregroundColor(colorForTableType(table.tableType, isActive: isActive))

            Text(table.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? PostgraceTheme.accentSky : (isHovered ? .primary : .secondary))
                .lineLimit(1)

            Spacer()

            if table.tableType != .table {
                Text(table.tableType.rawValue)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(colorForTableType(table.tableType, isActive: isActive))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            isActive ? PostgraceTheme.accentSkyMuted : (isHovered ? PostgraceTheme.surfaceHover : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            Rectangle()
                .fill(isActive ? PostgraceTheme.accentSky : Color.clear)
                .frame(width: 2),
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Open Data") {
                onOpenData()
            }
            Button("Open Structure") {
                onOpenStructure()
            }
            Divider()
            Button("Export Table Data…") {
                exportViewModel.startTableExport(schema: schema.name, table: table.name)
            }
            Button("Import Data to Table…") {
                let cols = schemaViewModel.columns["\(schema.name).\(table.name)"]?.map(\.name) ?? []
                importViewModel.startTableImport(schema: schema.name, table: table.name, tableColumns: cols)
            }
            Divider()
            Button("Copy Table Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(table.name, forType: .string)
            }
            Button("Copy Qualified Name (\"\(schema.name)\".\"\(table.name)\")") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\"\(schema.name)\".\"\(table.name)\"", forType: .string)
            }
            Button("Copy SELECT * Query") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("SELECT * FROM \"\(schema.name)\".\"\(table.name)\" LIMIT 100;", forType: .string)
            }
            Divider()
            Button("Query in SQL Editor") {
                onQueryInEditor()
            }
        }
    }

    private func iconForTableType(_ type: TableType) -> String {
        switch type {
        case .table: return "tablecells"
        case .view: return "eye"
        case .materializedView: return "eye.fill"
        case .foreignTable: return "link"
        }
    }

    private func colorForTableType(_ type: TableType, isActive: Bool) -> Color {
        if isActive { return PostgraceTheme.accentSky }
        switch type {
        case .table: return .secondary
        case .view: return PostgraceTheme.purpleSuper
        case .materializedView: return PostgraceTheme.purpleSuper
        case .foreignTable: return PostgraceTheme.amberRo
        }
    }
}
