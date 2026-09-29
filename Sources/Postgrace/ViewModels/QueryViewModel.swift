import Foundation
import Observation

public struct QueryHistoryItem: Identifiable {
    public let id: UUID
    public let query: String
    public let executedAt: Date
    public let duration: TimeInterval
    public let rowCount: Int
    
    public init(id: UUID = UUID(), query: String, executedAt: Date = Date(), duration: TimeInterval, rowCount: Int) {
        self.id = id
        self.query = query
        self.executedAt = executedAt
        self.duration = duration
        self.rowCount = rowCount
    }
}

@Observable
public class QueryViewModel {
    public var queryText: String = ""
    public var result: QueryResult?
    public var isExecuting: Bool = false
    public var executionError: String?
    public var queryHistory: [QueryHistoryItem] = []
    
    private let postgresService: PostgresService
    private var currentTask: Task<QueryResult, Error>?
    
    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }
    
    public func executeQuery() async {
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isExecuting = true
        executionError = nil
        
        let task = Task {
            try await postgresService.executeQuery(queryText)
        }
        self.currentTask = task
        
        do {
            let queryResult = try await task.value
            self.result = queryResult
            
            let historyItem = QueryHistoryItem(
                query: queryText,
                duration: queryResult.executionTime,
                rowCount: queryResult.rowsAffected
            )
            queryHistory.append(historyItem)
        } catch is CancellationError {
            executionError = "Query cancelled by user."
            self.result = nil
        } catch {
            if error.localizedDescription.lowercased().contains("cancel") {
                executionError = "Query cancelled by user."
            } else {
                executionError = error.localizedDescription
            }
            self.result = nil
        }
        
        self.currentTask = nil
        self.isExecuting = false
    }

    /// Cancels or aborts the currently running query.
    public func cancelQuery() {
        guard isExecuting else { return }
        currentTask?.cancel()
        currentTask = nil
        Task {
            await postgresService.cancelRunningQuery()
        }
        isExecuting = false
        executionError = "Query cancelled by user."
    }
    
    public func clearResult() {
        result = nil
        executionError = nil
    }
    
    public func loadHistoryItem(_ item: QueryHistoryItem) {
        queryText = item.query
    }
}
