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
    
    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }
    
    public func executeQuery() async {
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isExecuting = true
        executionError = nil
        
        do {
            let queryResult = try await postgresService.executeQuery(queryText)
            self.result = queryResult
            
            let historyItem = QueryHistoryItem(
                query: queryText,
                duration: queryResult.executionTime,
                rowCount: queryResult.rowsAffected
            )
            queryHistory.append(historyItem)
        } catch {
            executionError = error.localizedDescription
            self.result = nil
        }
        
        isExecuting = false
    }
    
    public func clearResult() {
        result = nil
        executionError = nil
    }
    
    public func loadHistoryItem(_ item: QueryHistoryItem) {
        queryText = item.query
    }
}
