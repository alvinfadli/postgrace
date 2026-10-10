import Foundation

/// Manages discovery and execution of official PostgreSQL CLI utilities (pg_dump, pg_restore, psql).
public final class PostgresToolchainService {

    public static let shared = PostgresToolchainService()

    private let standardSearchPaths = [
        "/opt/homebrew/bin",                                      // Apple Silicon Homebrew
        "/usr/local/bin",                                          // Intel Mac Homebrew / MacPorts
        "/Applications/Postgres.app/Contents/Versions/latest/bin", // Postgres.app
        "/usr/bin"
    ]

    /// Locates the specified executable URL across standard paths or user PATH.
    public func findExecutable(_ name: String) -> URL? {
        let fm = FileManager.default

        // 1. Check known macOS directories
        for dir in standardSearchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 2. Check PATH environment variable
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    public var isPgDumpAvailable: Bool {
        findExecutable("pg_dump") != nil
    }

    public var isPgRestoreAvailable: Bool {
        findExecutable("pg_restore") != nil
    }

    public var isPsqlAvailable: Bool {
        findExecutable("psql") != nil
    }

    /// Executes `pg_dump` with configuration and streams output.
    public func runDump(
        config: SavedConnection,
        password: String,
        arguments: [String],
        onLog: @escaping (String) -> Void
    ) async throws {
        guard let pgDumpURL = findExecutable("pg_dump") else {
            throw NSError(
                domain: "PostgresToolchain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "pg_dump was not found on this system. Install PostgreSQL client tools via Homebrew (`brew install libpq` or `brew install postgresql`)."]
            )
        }

        try await runProcess(
            executableURL: pgDumpURL,
            arguments: arguments,
            password: password,
            onLog: onLog
        )
    }

    /// Executes `pg_restore` with configuration.
    public func runRestore(
        config: SavedConnection,
        password: String,
        arguments: [String],
        onLog: @escaping (String) -> Void
    ) async throws {
        guard let pgRestoreURL = findExecutable("pg_restore") else {
            throw NSError(
                domain: "PostgresToolchain",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "pg_restore was not found on this system. Install PostgreSQL client tools via Homebrew (`brew install postgresql`)."]
            )
        }

        try await runProcess(
            executableURL: pgRestoreURL,
            arguments: arguments,
            password: password,
            onLog: onLog
        )
    }

    /// Reads and returns the Table of Contents (TOC) lines from a PostgreSQL dump file using `pg_restore -l`.
    public func listDumpTOC(fileURL: URL) async throws -> [String] {
        guard let pgRestoreURL = findExecutable("pg_restore") else { return [] }
        let process = Process()
        process.executableURL = pgRestoreURL
        process.arguments = ["-l", fileURL.path]
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.components(separatedBy: .newlines)
    }

    /// Executes `psql` to restore plain text SQL scripts.
    public func runPsql(
        config: SavedConnection,
        password: String,
        arguments: [String],
        onLog: @escaping (String) -> Void
    ) async throws {
        guard let psqlURL = findExecutable("psql") else {
            throw NSError(
                domain: "PostgresToolchain",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "psql was not found on this system. Install PostgreSQL tools via Homebrew (`brew install postgresql`)."]
            )
        }

        try await runProcess(
            executableURL: psqlURL,
            arguments: arguments,
            password: password,
            onLog: onLog
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        password: String,
        onLog: @escaping (String) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        // SEC-001: Decouple stdin so subprocess never blocks indefinitely on interactive terminal prompts
        process.standardInput = FileHandle.nullDevice

        // Inject password safely via environment variable (never exposed in ps command list)
        var env = ProcessInfo.processInfo.environment
        env["PGPASSWORD"] = password
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outHandle = pipe.fileHandleForReading
        let logBuffer = LogBuffer()

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                logBuffer.append(output)
                DispatchQueue.main.async {
                    onLog(output)
                }
            }
        }

        try process.run()

        // Non-blocking wait with Task cancellation support
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        outHandle.readabilityHandler = nil

        if Task.isCancelled {
            throw CancellationError()
        }

        if process.terminationStatus != 0 {
            let errorDetails = logBuffer.combined()
            let errorMsg = errorDetails.isEmpty
                ? "\(executableURL.lastPathComponent) exited with code \(process.terminationStatus)"
                : "\(executableURL.lastPathComponent) failed (\(process.terminationStatus)): \(errorDetails)"

            throw NSError(
                domain: "PostgresToolchain",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMsg]
            )
        }
    }
}

private final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var logs: [String] = []

    func append(_ string: String) {
        lock.lock()
        defer { lock.unlock() }
        logs.append(string)
        if logs.count > 50 {
            logs.removeFirst(logs.count - 50)
        }
    }

    func combined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return logs.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
