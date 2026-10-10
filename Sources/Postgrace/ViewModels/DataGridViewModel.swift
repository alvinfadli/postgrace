import Foundation
import Observation

/// ViewModel for browsing table data with pagination and visual multi-condition filtering.
@Observable
public class DataGridViewModel {
    public var result: QueryResult?
    public var isLoading: Bool = false
    public var currentPage: Int = 0
    public var pageSize: Int = 200
    public var totalRows: Int64 = 0
    public var error: String?

    /// The currently loaded schema and table (for pagination context).
    public var currentSchema: String?
    public var currentTable: String?

    /// The available column names in the current table (for dropdown selection).
    public var availableColumns: [String] = []

    /// Structured filter rules created by the user.
    public var filterRules: [FilterRule] = []

    /// Logical conjunction between multiple filter rules (AND / OR).
    public var filterConjunction: FilterConjunction = .and

    /// Compiled SQL WHERE expression sent to the backend.
    public var filterClause: String = ""

    /// Set of column names hidden from view in the table view.
    public var hiddenColumns: Set<String> = []

    private let postgresService: PostgresService
    private var currentLoadRequestId: UUID = UUID()

    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }

    /// Total number of pages based on totalRows and pageSize.
    public var totalPages: Int {
        guard totalRows > 0 else { return 0 }
        return max(1, Int((totalRows + Int64(pageSize) - 1) / Int64(pageSize)))
    }

    /// Whether there's a next page available.
    public var hasNextPage: Bool {
        currentPage < totalPages - 1
    }

    /// Whether there's a previous page available.
    public var hasPreviousPage: Bool {
        currentPage > 0
    }

    /// Builds a SQL WHERE expression from active filter rules.
    public func buildFilterClause() -> String {
        let validRules = filterRules.compactMap { $0.toSQLExpression() }
        guard !validRules.isEmpty else { return "" }
        return validRules.joined(separator: " \(filterConjunction.rawValue) ")
    }

    /// Adds a new filter rule defaulting to the first available column.
    public func addFilterRule(defaultColumn: String = "") {
        let col = !defaultColumn.isEmpty ? defaultColumn : (availableColumns.first ?? "")
        let rule = FilterRule(column: col, op: .equals, value: "")
        filterRules.append(rule)
    }

    /// Removes a filter rule by its UUID.
    public func removeFilterRule(id: UUID) {
        filterRules.removeAll(where: { $0.id == id })
    }

    /// Checks whether there is an active filter on a specific column.
    public func hasFilter(for column: String) -> Bool {
        filterRules.contains { $0.column == column }
    }

    /// Gets the first active filter rule for a specific column, if any.
    public func filterRule(for column: String) -> FilterRule? {
        filterRules.first { $0.column == column }
    }

    /// Sets or updates a filter rule on a specific column and immediately executes the query.
    public func setFilter(column: String, op: FilterOperator, value: String) async {
        if let idx = filterRules.firstIndex(where: { $0.column == column }) {
            filterRules[idx].op = op
            filterRules[idx].value = value
        } else {
            filterRules.append(FilterRule(column: column, op: op, value: value))
        }
        await applyFilter()
    }

    /// Removes all filter rules on a specific column and immediately refreshes the query.
    public func removeFilter(for column: String) async {
        filterRules.removeAll(where: { $0.column == column })
        await applyFilter()
    }

    // MARK: - Column Visibility Helpers

    /// Toggles the visibility of a column in the table view.
    public func toggleColumnVisibility(_ columnName: String) {
        if hiddenColumns.contains(columnName) {
            hiddenColumns.remove(columnName)
        } else {
            hiddenColumns.insert(columnName)
        }
    }

    /// Checks whether a column is currently visible.
    public func isColumnVisible(_ columnName: String) -> Bool {
        !hiddenColumns.contains(columnName)
    }

    /// Restores visibility for all columns.
    public func showAllColumns() {
        hiddenColumns.removeAll()
    }

    /// Hides all columns except an optional kept column (defaults to first available).
    public func hideAllColumns(except keepColumn: String? = nil) {
        let kept = keepColumn ?? availableColumns.first ?? ""
        hiddenColumns = Set(availableColumns.filter { $0 != kept })
    }

    /// Clears all filter rules and reloads the unfiltered table data.
    public func clearFilters() async {
        filterRules.removeAll()
        filterClause = ""
        currentPage = 0
        if let schema = currentSchema, let table = currentTable {
            await loadTableData(schema: schema, table: table)
        }
    }

    /// Load data for a specific table (resets to page 0).
    public func loadTableData(schema: String, table: String) async {
        let requestId = UUID()
        currentLoadRequestId = requestId

        currentSchema = schema
        currentTable = table
        currentPage = 0
        filterClause = buildFilterClause()
        isLoading = true
        error = nil

        do {
            let fetchedTotalRows = try await postgresService.fetchTableRowCount(schema: schema, table: table, filterClause: filterClause)
            guard currentLoadRequestId == requestId else { return }

            let fetchedResult = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: 0
            )
            guard currentLoadRequestId == requestId else { return }

            totalRows = fetchedTotalRows
            result = fetchedResult
            availableColumns = fetchedResult.columns.map(\.name)
            isLoading = false
        } catch {
            guard currentLoadRequestId == requestId else { return }
            isLoading = false
            if Task.isCancelled || error is CancellationError || error.localizedDescription.contains("Query cancelled") {
                return
            }
            self.error = error.localizedDescription
            result = nil
        }
    }

    /// Applies the current structured filter rules and resets to page 0.
    public func applyFilter() async {
        guard let schema = currentSchema, let table = currentTable else { return }
        let requestId = UUID()
        currentLoadRequestId = requestId

        filterClause = buildFilterClause()
        currentPage = 0
        isLoading = true
        error = nil

        do {
            let fetchedTotalRows = try await postgresService.fetchTableRowCount(schema: schema, table: table, filterClause: filterClause)
            guard currentLoadRequestId == requestId else { return }

            let fetchedResult = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: 0
            )
            guard currentLoadRequestId == requestId else { return }

            totalRows = fetchedTotalRows
            result = fetchedResult
            availableColumns = fetchedResult.columns.map(\.name)
            isLoading = false
        } catch {
            guard currentLoadRequestId == requestId else { return }
            isLoading = false
            if Task.isCancelled || error is CancellationError || error.localizedDescription.contains("Query cancelled") {
                return
            }
            self.error = error.localizedDescription
        }
    }

    /// Navigate to the next page.
    public func nextPage() async {
        guard hasNextPage, let schema = currentSchema, let table = currentTable else { return }
        currentPage += 1
        await fetchCurrentPage(schema: schema, table: table)
    }

    /// Navigate to the previous page.
    public func previousPage() async {
        guard hasPreviousPage, let schema = currentSchema, let table = currentTable else { return }
        currentPage -= 1
        await fetchCurrentPage(schema: schema, table: table)
    }

    /// Refresh the current page.
    public func refresh() async {
        guard let schema = currentSchema, let table = currentTable else { return }
        await fetchCurrentPage(schema: schema, table: table)
    }

    private func fetchCurrentPage(schema: String, table: String) async {
        let requestId = UUID()
        currentLoadRequestId = requestId

        isLoading = true
        error = nil

        do {
            let fetchedResult = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: currentPage * pageSize
            )
            guard currentLoadRequestId == requestId else { return }

            result = fetchedResult
            availableColumns = fetchedResult.columns.map(\.name)
            isLoading = false
        } catch {
            guard currentLoadRequestId == requestId else { return }
            isLoading = false
            if Task.isCancelled || error is CancellationError || error.localizedDescription.contains("Query cancelled") {
                return
            }
            self.error = error.localizedDescription
        }
    }

    // MARK: - Safe Mode Protections (FR-5)

    /// Evaluates whether Safe Mode is active on the current active connection.
    public func isSafeModeActive() async -> Bool {
        let config = await postgresService.activeConfig
        return config?.isSafeModeEffective ?? false
    }

    /// Evaluates safety for a proposed direct cell edit.
    public func evaluateCellUpdateSafety(column: String, primaryKey: String, newValue: String) -> SQLSafetyCheckResult {
        let table = currentTable ?? "table"
        let sql = "UPDATE \"\(table)\" SET \"\(column)\" = '\(newValue)' WHERE id = \(primaryKey);"
        return SQLSafetyAnalyzer.analyze(sql)
    }

    /// Evaluates safety for a proposed direct row deletion.
    public func evaluateRowDeletionSafety(primaryKeyColumn: String, primaryKeyValue: String) -> SQLSafetyCheckResult {
        let table = currentTable ?? "table"
        let sql = "DELETE FROM \"\(table)\" WHERE \"\(primaryKeyColumn)\" = \(primaryKeyValue);"
        return SQLSafetyAnalyzer.analyze(sql)
    }
}
