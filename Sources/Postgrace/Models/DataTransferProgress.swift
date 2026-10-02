import Foundation

/// Lifecycle status for an export or import task.
public enum DataTransferStatus: Equatable {
    case idle
    case inProgress
    case completed(String)
    case failed(String)
    case cancelled
}

/// Real-time metrics and progress tracking for data transfers.
public struct DataTransferProgress: Equatable {
    public var status: DataTransferStatus = .idle
    public var rowsProcessed: Int64 = 0
    public var totalRows: Int64? = nil
    public var bytesTransferred: Int64 = 0
    public var currentOperation: String = ""
    public var startTime: Date? = nil
    public var errorLog: [String] = []

    public init() {}

    public var isRunning: Bool {
        status == .inProgress
    }

    public var fractionCompleted: Double? {
        guard let total = totalRows, total > 0 else { return nil }
        return min(1.0, Double(rowsProcessed) / Double(total))
    }

    public var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    public var throughputRowsPerSecond: Double {
        let elapsed = elapsedTime
        guard elapsed > 0 else { return 0 }
        return Double(rowsProcessed) / elapsed
    }

    public var formattedThroughput: String {
        let rps = throughputRowsPerSecond
        if rps >= 1_000 {
            return String(format: "%.1fk rows/s", rps / 1_000)
        }
        return "\(Int(rps)) rows/s"
    }

    public var formattedBytes: String {
        let b = Double(bytesTransferred)
        if b >= 1_000_000_000 {
            return String(format: "%.2f GB", b / 1_000_000_000)
        } else if b >= 1_000_000 {
            return String(format: "%.1f MB", b / 1_000_000)
        } else if b >= 1_000 {
            return String(format: "%.1f KB", b / 1_000)
        }
        return "\(bytesTransferred) bytes"
    }
}
