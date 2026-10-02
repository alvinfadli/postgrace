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

        // Inject password safely via environment variable (never exposed in ps command list)
        var env = ProcessInfo.processInfo.environment
        env["PGPASSWORD"] = password
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outHandle = pipe.fileHandleForReading

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    onLog(output)
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        outHandle.readabilityHandler = nil

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "PostgresToolchain",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "\(executableURL.lastPathComponent) exited with code \(process.terminationStatus)"]
            )
        }
    }
}
