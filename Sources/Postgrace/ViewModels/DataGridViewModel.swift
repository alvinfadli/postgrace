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

    private let postgresService: PostgresService

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
        currentSchema = schema
        currentTable = table
        currentPage = 0
        filterClause = buildFilterClause()
        isLoading = true
        error = nil

        do {
            totalRows = try await postgresService.fetchTableRowCount(schema: schema, table: table, filterClause: filterClause)
            result = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: 0
            )
            if let res = result {
                availableColumns = res.columns.map(\.name)
            }
        } catch {
            self.error = error.localizedDescription
            result = nil
        }

        isLoading = false
    }

    /// Applies the current structured filter rules and resets to page 0.
    public func applyFilter() async {
        guard let schema = currentSchema, let table = currentTable else { return }
        filterClause = buildFilterClause()
        currentPage = 0
        isLoading = true
        error = nil

        do {
            totalRows = try await postgresService.fetchTableRowCount(schema: schema, table: table, filterClause: filterClause)
            result = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: 0
            )
            if let res = result {
                availableColumns = res.columns.map(\.name)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
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
        isLoading = true
        error = nil

        do {
            result = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                filterClause: filterClause,
                limit: pageSize,
                offset: currentPage * pageSize
            )
            if let res = result {
                availableColumns = res.columns.map(\.name)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
