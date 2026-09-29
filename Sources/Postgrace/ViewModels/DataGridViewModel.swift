import Foundation
import Observation

/// ViewModel for browsing table data with pagination.
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

    /// Load data for a specific table (resets to page 0).
    public func loadTableData(schema: String, table: String) async {
        currentSchema = schema
        currentTable = table
        currentPage = 0
        isLoading = true
        error = nil

        do {
            totalRows = try await postgresService.fetchTableRowCount(schema: schema, table: table)
            result = try await postgresService.fetchTableData(
                schema: schema,
                table: table,
                limit: pageSize,
                offset: 0
            )
        } catch {
            self.error = error.localizedDescription
            result = nil
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
                limit: pageSize,
                offset: currentPage * pageSize
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
