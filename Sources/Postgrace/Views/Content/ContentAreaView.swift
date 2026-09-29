import SwiftUI

/// Main content area hosting the workspace tab bar and the active tab's view.
struct ContentAreaView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(DataGridViewModel.self) private var dataGridViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Workspace Tab Bar
            WorkspaceTabBarView()

            // Active Tab Content
            if let activeTab = tabViewModel.activeTab {
                switch activeTab.type {
                case .table(let schema, let table):
                    tableDataView(schema: schema, table: table)
                case .query:
                    QueryEditorView()
                case .structure(let schema, let table):
                    tableStructureView(schema: schema, table: table)
                }
            } else {
                QueryEditorView()
            }
        }
    }

    // MARK: - Table Data View with Quick Filter Bar

    @ViewBuilder
    private func tableDataView(schema: String, table: String) -> some View {
        @Bindable var dataVM = dataGridViewModel

        VStack(spacing: 0) {
            // Quick Filter Bar directly above grid
            QuickFilterBarView(filterClause: $dataVM.filterClause) {
                Task {
                    await dataGridViewModel.applyFilter()
                }
            }

            // Data Grid or Loading / Error states
            if dataGridViewModel.isLoading {
                ProgressView("Loading data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = dataGridViewModel.error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Query Error")
                        .font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Reset Filter & Retry") {
                        dataGridViewModel.filterClause = ""
                        Task {
                            await dataGridViewModel.loadTableData(schema: schema, table: table)
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = dataGridViewModel.result {
                DataGridView(queryResult: result)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Fetching table data…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(schema).\(table)") {
            await dataGridViewModel.loadTableData(schema: schema, table: table)
        }
    }

    // MARK: - Structure View Helper

    @ViewBuilder
    private func tableStructureView(schema: String, table: String) -> some View {
        let schemaInfo = schemaViewModel.schemas.first(where: { $0.name == schema }) ?? SchemaInfo(name: schema, oid: 0)
        let tableInfo = schemaViewModel.tables[schema]?.first(where: { $0.name == table }) ?? TableInfo(
            schema: schema,
            name: table,
            oid: 0,
            estimatedRowCount: 0,
            tableType: .table
        )
        TableStructureView(schema: schemaInfo, table: tableInfo)
    }
}
