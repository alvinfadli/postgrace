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

public struct StatementResult: Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let statement: String
    public let result: QueryResult?
    public let error: String?
    public let duration: TimeInterval

    public var isSuccess: Bool { error == nil }
    public var rowCount: Int { result?.rows.count ?? result?.rowsAffected ?? 0 }
    public var columnCount: Int { result?.columns.count ?? 0 }

    public init(
        id: UUID = UUID(),
        index: Int,
        statement: String,
        result: QueryResult? = nil,
        error: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.index = index
        self.statement = statement
        self.result = result
        self.error = error
        self.duration = duration
    }
}

@Observable
public class QueryViewModel {
    public var queryText: String = ""
    public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    public var selectedText: String = ""
    public var statementResults: [StatementResult] = []
    public var selectedStatementIndex: Int = 0
    public var isExecuting: Bool = false
    public var executionError: String?
    public var queryHistory: [QueryHistoryItem] = []

    private var _result: QueryResult?

    /// Active or legacy query result for backward compatibility with views and tests.
    public var result: QueryResult? {
        get {
            if statementResults.indices.contains(selectedStatementIndex) {
                return statementResults[selectedStatementIndex].result ?? _result
            }
            return _result
        }
        set {
            _result = newValue
        }
    }

    private let postgresService: PostgresService
    private var currentTask: Task<[StatementResult], Error>?

    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }

    // MARK: - Query Analysis & Helpers

    /// All statement spans found in `queryText`.
    public var statementSpans: [SQLStatementSpan] {
        SQLScriptSplitter.splitWithSpans(queryText)
    }

    /// Number of SQL statements currently in the editor.
    public var statementCount: Int {
        statementSpans.count
    }

    /// The statement span currently at or closest to the cursor.
    public var statementAtCursor: SQLStatementSpan? {
        SQLScriptSplitter.statement(at: selectedRange.location, in: queryText)
    }

    /// The statement result currently selected in the UI.
    public var activeStatementResult: StatementResult? {
        if statementResults.indices.contains(selectedStatementIndex) {
            return statementResults[selectedStatementIndex]
        }
        return nil
    }

    // MARK: - Execution

    /// Executes multiple statements sequentially, capturing results, timing, and errors per statement.
    public func executeStatements(_ statementsToRun: [String]) async {
        guard !isExecuting else { return }
        let validStatements = statementsToRun
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !validStatements.isEmpty else { return }

        isExecuting = true
        executionError = nil
        statementResults = []
        selectedStatementIndex = 0
        _result = nil

        var tempResults: [StatementResult] = []

        let task = Task { [postgresService] () -> [StatementResult] in
            for (index, stmt) in validStatements.enumerated() {
                try Task.checkCancellation()

                let start = Date()
                do {
                    let queryResult = try await postgresService.executeQuery(stmt)
                    let duration = Date().timeIntervalSince(start)
                    let item = StatementResult(
                        index: index,
                        statement: stmt,
                        result: queryResult,
                        error: nil,
                        duration: duration
                    )
                    tempResults.append(item)
                } catch is CancellationError {
                    let duration = Date().timeIntervalSince(start)
                    let item = StatementResult(
                        index: index,
                        statement: stmt,
                        result: nil,
                        error: "Query cancelled by user.",
                        duration: duration
                    )
                    tempResults.append(item)
                    throw CancellationError()
                } catch {
                    let duration = Date().timeIntervalSince(start)
                    let errorDesc = error.localizedDescription
                    let item = StatementResult(
                        index: index,
                        statement: stmt,
                        result: nil,
                        error: errorDesc,
                        duration: duration
                    )
                    tempResults.append(item)
                    throw error
                }
            }
            return tempResults
        }
        self.currentTask = task

        do {
            let finalResults = try await task.value
            self.statementResults = finalResults
            for stmtResult in finalResults {
                let historyItem = QueryHistoryItem(
                    query: stmtResult.statement,
                    duration: stmtResult.duration,
                    rowCount: stmtResult.rowCount
                )
                queryHistory.append(historyItem)
            }
            if let lastTableIndex = finalResults.lastIndex(where: { !($0.result?.columns.isEmpty ?? true) }) {
                self.selectedStatementIndex = lastTableIndex
            } else {
                self.selectedStatementIndex = max(0, finalResults.count - 1)
            }
        } catch is CancellationError {
            self.statementResults = tempResults
            self.executionError = "Query cancelled by user."
            self.selectedStatementIndex = max(0, tempResults.count - 1)
        } catch {
            self.statementResults = tempResults
            if error.localizedDescription.lowercased().contains("cancel") {
                self.executionError = "Query cancelled by user."
            } else {
                self.executionError = error.localizedDescription
            }
            self.selectedStatementIndex = max(0, tempResults.count - 1)
        }

        self.currentTask = nil
        self.isExecuting = false
    }

    /// Executes only the currently selected text, or the statement at the cursor.
    public func executeCurrentOrSelected() async {
        let trimmedSelected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelected.isEmpty {
            let stmts = SQLScriptSplitter.split(trimmedSelected)
            await executeStatements(stmts.isEmpty ? [trimmedSelected] : stmts)
            return
        }

        if let span = statementAtCursor {
            await executeStatements([span.statement])
            return
        }

        let all = SQLScriptSplitter.split(queryText)
        if let first = all.first {
            await executeStatements([first])
        }
    }

    /// Executes all statements in the query editor.
    public func executeAll() async {
        let stmts = SQLScriptSplitter.split(queryText)
        guard !stmts.isEmpty else { return }
        await executeStatements(stmts)
    }

    /// Primary entry point. If multiple statements exist and text is selected, executes the selection.
    /// Otherwise executes all statements in the editor sequentially.
    public func executeQuery() async {
        guard !isExecuting else { return }
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let trimmedSelected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelected.isEmpty {
            let stmts = SQLScriptSplitter.split(trimmedSelected)
            await executeStatements(stmts.isEmpty ? [trimmedSelected] : stmts)
            return
        }

        let all = SQLScriptSplitter.split(queryText)
        await executeStatements(all.isEmpty ? [queryText] : all)
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
        _result = nil
        statementResults = []
        selectedStatementIndex = 0
        executionError = nil
    }

    public func loadHistoryItem(_ item: QueryHistoryItem) {
        queryText = item.query
    }

    /// Evaluates whether the given SQL text contains dangerous or unbounded mutations.
    public func evaluateSafety(for sql: String? = nil) -> SQLSafetyCheckResult {
        let text = sql ?? queryText
        return SQLSafetyAnalyzer.analyze(text)
    }
}
