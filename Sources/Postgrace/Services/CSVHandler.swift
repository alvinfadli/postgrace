import Foundation

/// RFC 4180 compliant CSV encoder and streaming parser.
public enum CSVHandler {

    // MARK: - CSV Encoding

    /// Encodes an array of cell string values into a single RFC 4180 CSV line.
    public static func encodeRow(_ values: [String], delimiter: String = ",", sanitizeFormulas: Bool = true) -> String {
        let escaped = values.map { escapeField($0, delimiter: delimiter, sanitizeFormulas: sanitizeFormulas) }
        return escaped.joined(separator: delimiter)
    }

    /// Escapes an individual field according to RFC 4180 rules, with optional formula injection defense (CWE-1236).
    public static func escapeField(_ value: String, delimiter: String = ",", sanitizeFormulas: Bool = true) -> String {
        var processed = value
        if sanitizeFormulas && isFormulaTrigger(processed) {
            processed = "'" + processed
        }

        let needsQuotes = processed.contains(delimiter) ||
            processed.contains("\"") ||
            processed.contains("\n") ||
            processed.contains("\r")

        if needsQuotes {
            let doubledQuotes = processed.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubledQuotes)\""
        }
        return processed
    }

    /// Detects potential spreadsheet formula execution triggers (=, @, \t, \r, and unparsed +, -).
    public static func isFormulaTrigger(_ value: String) -> Bool {
        guard let first = value.first else { return false }
        if first == "=" || first == "@" || first == "\t" || first == "\r" {
            return true
        }
        if (first == "+" || first == "-") && Double(value) == nil {
            return true
        }
        return false
    }

    // MARK: - CSV Parsing

    /// Parses a CSV line or multiline chunk into fields conforming to RFC 4180.
    public static func parseLine(_ line: String, delimiter: Character = ",") -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]

            if inQuotes {
                if char == "\"" {
                    let nextIndex = line.index(after: index)
                    if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == delimiter {
                    fields.append(currentField)
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            index = line.index(after: index)
        }

        fields.append(currentField)
        return fields
    }

    /// Inspects the first non-empty lines of a CSV file to extract headers and preview rows.
    public static func inspect(url: URL, delimiter: Character = ",", maxPreviewRows: Int = 5) throws -> (headers: [String], previewRows: [[String]]) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw NSError(domain: "CSVHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read file as UTF-8 or ASCII text."])
        }

        var lines: [String] = []
        content.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(line)
                if lines.count >= maxPreviewRows + 1 {
                    stop = true
                }
            }
        }

        guard let first = lines.first else {
            return ([], [])
        }

        let headers = parseLine(first, delimiter: delimiter)
        var preview: [[String]] = []
        for line in lines.dropFirst() {
            preview.append(parseLine(line, delimiter: delimiter))
        }

        return (headers, preview)
    }

    /// Streaming parser reading a CSV file line by line and yielding records in batches.
    public static func parseInBatches(
        url: URL,
        delimiter: Character = ",",
        hasHeaders: Bool = true,
        batchSize: Int = 250,
        onBatch: @escaping (_ rows: [[String]]) async throws -> Void
    ) async throws -> Int64 {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw NSError(domain: "CSVHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read file as text."])
        }

        var isFirst = true
        var batch: [[String]] = []
        var totalRows: Int64 = 0

        var currentLine = ""
        var inQuotes = false

        for char in content {
            if char == "\"" {
                inQuotes.toggle()
                currentLine.append(char)
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if !currentLine.isEmpty {
                    if isFirst && hasHeaders {
                        isFirst = false
                    } else {
                        let parsed = parseLine(currentLine, delimiter: delimiter)
                        batch.append(parsed)
                        totalRows += 1

                        if batch.count >= batchSize {
                            try await onBatch(batch)
                            batch.removeAll(keepingCapacity: true)
                        }
                    }
                    currentLine = ""
                }
            } else {
                currentLine.append(char)
            }
        }

        // Process trailing row if any
        if !currentLine.isEmpty {
            if isFirst && hasHeaders {
                // Was only a header row
            } else {
                let parsed = parseLine(currentLine, delimiter: delimiter)
                batch.append(parsed)
                totalRows += 1
            }
        }

        if !batch.isEmpty {
            try await onBatch(batch)
        }

        return totalRows
    }
}
