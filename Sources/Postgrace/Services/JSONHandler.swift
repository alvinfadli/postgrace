import Foundation

/// JSON encoder and parser supporting standard JSON arrays and Newline Delimited JSON (NDJSON).
public enum JSONHandler {

    /// Converts a dictionary of column names to values into a JSON string line.
    public static func encodeRecord(_ record: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.fragmentsAllowed]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Inspects a JSON file to determine headers and sample records.
    public static func inspect(url: URL, maxPreviewRows: Int = 5) throws -> (headers: [String], previewRows: [[String: String]]) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // Try standard JSON array first
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let array = jsonObject as? [[String: Any]] {
            var allKeys: [String] = []
            var keySet = Set<String>()

            for dict in array.prefix(10) {
                for key in dict.keys {
                    if !keySet.contains(key) {
                        keySet.insert(key)
                        allKeys.append(key)
                    }
                }
            }

            var previews: [[String: String]] = []
            for dict in array.prefix(maxPreviewRows) {
                var row: [String: String] = [:]
                for key in allKeys {
                    if let val = dict[key] {
                        row[key] = "\(val)"
                    } else {
                        row[key] = ""
                    }
                }
                previews.append(row)
            }
            return (allKeys, previews)
        }

        // Try NDJSON (line by line)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSONHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format."])
        }

        var allKeys: [String] = []
        var keySet = Set<String>()
        var previews: [[String: String]] = []

        content.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let lineData = trimmed.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] {
                for key in dict.keys {
                    if !keySet.contains(key) {
                        keySet.insert(key)
                        allKeys.append(key)
                    }
                }
                var row: [String: String] = [:]
                for (k, v) in dict {
                    row[k] = "\(v)"
                }
                previews.append(row)
                if previews.count >= maxPreviewRows {
                    stop = true
                }
            }
        }

        return (allKeys, previews)
    }

    /// Reads a JSON file in batches of records for streaming import.
    public static func parseInBatches(
        url: URL,
        batchSize: Int = 250,
        onBatch: @escaping (_ records: [[String: String]]) async throws -> Void
    ) async throws -> Int64 {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // Standard JSON Array
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let array = jsonObject as? [[String: Any]] {
            var batch: [[String: String]] = []
            var totalCount: Int64 = 0

            for dict in array {
                var stringDict: [String: String] = [:]
                for (k, v) in dict {
                    stringDict[k] = "\(v)"
                }
                batch.append(stringDict)
                totalCount += 1

                if batch.count >= batchSize {
                    try await onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if !batch.isEmpty {
                try await onBatch(batch)
            }
            return totalCount
        }

        // Fallback: NDJSON
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSONHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read JSON as UTF-8 string."])
        }

        var batch: [[String: String]] = []
        var totalCount: Int64 = 0

        // Stream line-by-line using substring slices to avoid allocating array of all lines in RAM
        var lineStart = content.startIndex
        while lineStart < content.endIndex {
            let lineEnd = content[lineStart...].firstIndex(where: { $0 == "\n" || $0 == "\r" }) ?? content.endIndex
            let lineSlice = content[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)

            if !lineSlice.isEmpty,
               let lineData = lineSlice.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] {
                var stringDict: [String: String] = [:]
                for (k, v) in dict {
                    stringDict[k] = "\(v)"
                }
                batch.append(stringDict)
                totalCount += 1

                if batch.count >= batchSize {
                    try await onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if lineEnd < content.endIndex {
                var nextStart = content.index(after: lineEnd)
                if content[lineEnd] == "\r" && nextStart < content.endIndex && content[nextStart] == "\n" {
                    nextStart = content.index(after: nextStart)
                }
                lineStart = nextStart
            } else {
                break
            }
        }

        if !batch.isEmpty {
            try await onBatch(batch)
        }

        return totalCount
    }
}
