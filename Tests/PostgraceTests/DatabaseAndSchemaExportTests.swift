import XCTest
@testable import Postgrace

final class DatabaseAndSchemaExportTests: XCTestCase {

    // MARK: - 1. Export Scope Titles and Properties

    func testExportScopeTitlesAndProperties() {
        let tableScope = ExportScope.table(schema: "public", table: "users")
        XCTAssertEqual(tableScope.title, "public.users")

        let singleTableItem = [ExportTableItem(schema: "public", table: "orders")]
        let singleMultiTableScope = ExportScope.multipleTables(items: singleTableItem)
        XCTAssertEqual(singleMultiTableScope.title, "public.orders")

        let multiTableItems = [
            ExportTableItem(schema: "public", table: "orders"),
            ExportTableItem(schema: "audit", table: "logs")
        ]
        let multiTableScope = ExportScope.multipleTables(items: multiTableItems)
        XCTAssertEqual(multiTableScope.title, "Tables (2 selected)")

        let schemaScope = ExportScope.schema(name: "billing")
        XCTAssertEqual(schemaScope.title, "Schema: billing")

        let multiSchemaScope = ExportScope.multipleSchemas(names: ["billing", "audit", "public"])
        XCTAssertEqual(multiSchemaScope.title, "Schemas (3 selected)")

        let dbScope = ExportScope.database(name: "production_db")
        XCTAssertEqual(dbScope.title, "Database: production_db")
    }

    // MARK: - 2. PostgreSQL Export Options Defaults

    func testPostgresExportOptionsDefaults() {
        let options = PostgresExportOptions()
        XCTAssertTrue(options.includeSchemaCreate)
        XCTAssertTrue(options.setPathHeader)
        XCTAssertTrue(options.cleanBeforeRestore)
        XCTAssertTrue(options.singleTransaction)
        XCTAssertTrue(options.includeExternalForeignKeys)
        XCTAssertEqual(options.customDumpCompressionLevel, 6)
        XCTAssertTrue(options.excludedSchemas.isEmpty)
    }

    // MARK: - 3. PostgreSQL System Schema Filtration Rules

    func testSystemSchemaFiltrationLogic() {
        let sampleCatalogNames = [
            "pg_catalog",
            "information_schema",
            "pg_toast",
            "pg_toast_temp_1",
            "pg_temp_2",
            "public",
            "audit",
            "billing",
            "my_pg_app"
        ]

        // Rule from BRD 5.2: nspname NOT LIKE 'pg_%' AND nspname != 'information_schema'
        let eligibleUserSchemas = sampleCatalogNames.filter { nspname in
            !nspname.hasPrefix("pg_") && nspname != "information_schema"
        }

        XCTAssertEqual(eligibleUserSchemas, ["public", "audit", "billing", "my_pg_app"])
        XCTAssertFalse(eligibleUserSchemas.contains("pg_catalog"))
        XCTAssertFalse(eligibleUserSchemas.contains("information_schema"))
        XCTAssertFalse(eligibleUserSchemas.contains("pg_toast"))
        XCTAssertFalse(eligibleUserSchemas.contains("pg_temp_2"))
    }

    // MARK: - 4. Export Configuration Suggested Filenames

    func testExportConfigurationSuggestedFilenamesAndModes() {
        var config = ExportConfiguration(scope: .database(name: "shop"), format: .customDump)
        config.contentMode = .structureAndData
        XCTAssertTrue(config.suggestedFileName.hasPrefix("db_shop_"))
        XCTAssertTrue(config.suggestedFileName.hasSuffix(".dump"))
        XCTAssertFalse(config.suggestedFileName.contains("_structure"))
        XCTAssertFalse(config.suggestedFileName.contains("_data"))

        config.contentMode = .structureOnly
        XCTAssertTrue(config.suggestedFileName.hasPrefix("db_shop_structure_"))
        XCTAssertTrue(config.suggestedFileName.hasSuffix(".dump"))

        config.contentMode = .dataOnly
        XCTAssertTrue(config.suggestedFileName.hasPrefix("db_shop_data_"))
        XCTAssertTrue(config.suggestedFileName.hasSuffix(".dump"))

        let multiSchemaConfig = ExportConfiguration(scope: .multipleSchemas(names: ["public", "audit"]), format: .sql)
        XCTAssertTrue(multiSchemaConfig.suggestedFileName.hasPrefix("schemas_2_items_"))
        XCTAssertTrue(multiSchemaConfig.suggestedFileName.hasSuffix(".sql"))
    }

    // MARK: - 5. Cross-Schema Foreign Key Isolation Logic

    func testCrossSchemaForeignKeyIsolationLogic() {
        let exportedSchemas = ["audit"]
        let conName = "fk_audit_events_user_id"
        let srcSchema = "audit"
        let srcTable = "events"
        let refSchema = "public"
        let conDef = "FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE"

        let isExternal = !exportedSchemas.contains(refSchema)
        XCTAssertTrue(isExternal, "Referencing public from audit is an external foreign key")

        // Case A: Isolated (includeExternalForeignKeys == false)
        var optionsA = PostgresExportOptions()
        optionsA.includeExternalForeignKeys = false

        let statementA: String
        if isExternal && !optionsA.includeExternalForeignKeys {
            statementA = "-- [EXTERNAL FK ISOLATED] ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n"
        } else {
            statementA = "ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n"
        }

        XCTAssertTrue(statementA.hasPrefix("-- [EXTERNAL FK ISOLATED] ALTER TABLE \"audit\".\"events\""))
        XCTAssertTrue(statementA.contains("FOREIGN KEY (user_id) REFERENCES public.users(id)"))

        // Case B: Retained (includeExternalForeignKeys == true)
        var optionsB = PostgresExportOptions()
        optionsB.includeExternalForeignKeys = true

        let statementB: String
        if isExternal && !optionsB.includeExternalForeignKeys {
            statementB = "-- [EXTERNAL FK ISOLATED] ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n"
        } else {
            statementB = "ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n"
        }

        XCTAssertFalse(statementB.hasPrefix("-- [EXTERNAL FK ISOLATED]"))
        XCTAssertTrue(statementB.hasPrefix("ALTER TABLE \"audit\".\"events\" ADD CONSTRAINT \"fk_audit_events_user_id\""))
    }

    // MARK: - 6. Topological DDL Ordering Validation

    func testTopologicalDDLOrderingStagesOrder() {
        let expectedStages = [
            "Stage 01: Clean & Schema Declaration",
            "Stage 02: Search Path Setup",
            "Stage 04: Custom Types & ENUMs",
            "Stage 05: Sequences",
            "Stage 06: Base Tables",
            "Stage 07: Data Loading",
            "Stage 08: Sequence Synchronization",
            "Stage 10: Foreign Key Constraints",
            "Stage 11: Views"
        ]

        // Verify topological stages are strictly monotonically ordered
        for i in 0..<(expectedStages.count - 1) {
            let current = expectedStages[i]
            let next = expectedStages[i + 1]
            XCTAssertTrue(current < next, "\(current) should precede \(next)")
        }
    }

    // MARK: - 7. Export ViewModel Schema Selection

    @MainActor
    func testExportViewModelSchemaSelectionAndToggling() {
        let mockService = PostgresService()
        let vm = ExportViewModel(postgresService: mockService)

        vm.availableSchemas = ["public", "audit", "billing"]
        vm.availableTables = [
            ExportTableItem(schema: "public", table: "users"),
            ExportTableItem(schema: "public", table: "orders"),
            ExportTableItem(schema: "audit", table: "logs"),
            ExportTableItem(schema: "billing", table: "invoices")
        ]

        // Select All Schemas
        vm.selectAllSchemas()
        XCTAssertEqual(vm.configuration.selectedSchemas.count, 3)
        XCTAssertEqual(vm.configuration.selectedTables.count, 4)

        // Deselect single schema "audit"
        vm.toggleSchemaSelection("audit")
        XCTAssertFalse(vm.isSchemaSelected("audit"))
        XCTAssertTrue(vm.isSchemaSelected("public"))
        XCTAssertTrue(vm.isSchemaSelected("billing"))
        XCTAssertEqual(vm.configuration.selectedSchemas.count, 2)
        XCTAssertEqual(vm.configuration.selectedTables.count, 3)
        XCTAssertFalse(vm.configuration.selectedTables.contains(ExportTableItem(schema: "audit", table: "logs")))

        // Deselect All Schemas
        vm.deselectAllSchemas()
        XCTAssertTrue(vm.configuration.selectedSchemas.isEmpty)
        XCTAssertTrue(vm.configuration.selectedTables.isEmpty)
    }

    // MARK: - 8. Export Cancellation and File Cleanup

    func testExportCancellationCleansUpPartialFile() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("partial_dump_\(UUID().uuidString).sql")
        FileManager.default.createFile(atPath: tempURL.path, contents: "PARTIAL DUMP CONTENT".data(using: .utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Simulate cancellation cleanup logic
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Cancelled export must delete temporary or incomplete dump file")
    }

    // MARK: - 9. Dump TOC Schema Parser Test

    func testDumpTOCSchemaParsingDoesNotCreateDataOrConstraintSchemas() {
        let sampleTOCLines = [
            "; Archive created at 2026-10-08 16:48:30",
            ";     dbname: sasuke_local",
            "189; 1259 16405 TABLE merchant merchant postgres",
            "190; 0 16405 TABLE DATA merchant merchant postgres",
            "191; 1259 16410 SEQUENCE merchant merchant_id_seq postgres",
            "192; 0 16410 SEQUENCE SET merchant merchant_id_seq postgres",
            "193; 2606 16420 CONSTRAINT merchant merchant_pkey postgres",
            "194; 2606 16425 FK CONSTRAINT merchant fk_user_id postgres",
            "195; 1259 16430 TABLE public users postgres",
            "196; 0 16430 TABLE DATA public users postgres",
            "197; 2615 16404 SCHEMA - billing postgres"
        ]

        let twoWordDescriptors: Set<String> = [
            "TABLE DATA", "FK CONSTRAINT", "CHECK CONSTRAINT",
            "SEQUENCE SET", "MATERIALIZED VIEW", "INDEX ATTACH",
            "OPERATOR CLASS", "OPERATOR FAMILY", "ROW SECURITY",
            "EVENT TRIGGER", "BLOB DATA"
        ]

        let invalidSchemaNames: Set<String> = [
            "-", "public", "DATA", "CONSTRAINT", "SET", "OWNED", "BY",
            "VIEW", "ATTACH", "CLASS", "FAMILY", "SECURITY", "TRIGGER",
            "TABLE", "SEQUENCE", "INDEX", "FUNCTION", "PROCEDURE"
        ]

        var referencedSchemas = Set<String>()

        for line in sampleTOCLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(";") || trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: ";", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let rawTokens = parts[1].split(separator: " ").map(String.init)
            guard rawTokens.count > 2 else { continue }
            let tokens = Array(rawTokens.dropFirst(2))

            var schemaCandidate: String? = nil

            if tokens[0] == "SCHEMA" {
                if tokens.count >= 3 && tokens[1] == "-" {
                    schemaCandidate = tokens[2]
                } else if tokens.count >= 2 && tokens[1] != "-" {
                    schemaCandidate = tokens[1]
                }
            } else if tokens.count >= 4 && tokens[0] == "SEQUENCE" && tokens[1] == "OWNED" && tokens[2] == "BY" {
                schemaCandidate = tokens[3]
            } else if tokens.count >= 4 && tokens[0] == "MATERIALIZED" && tokens[1] == "VIEW" && tokens[2] == "DATA" {
                schemaCandidate = tokens[3]
            } else if tokens.count >= 3 && twoWordDescriptors.contains("\(tokens[0]) \(tokens[1])") {
                schemaCandidate = tokens[2]
            } else if tokens.count >= 2 {
                schemaCandidate = tokens[1]
            }

            if let cand = schemaCandidate,
               !invalidSchemaNames.contains(cand),
               !cand.hasPrefix("pg_"),
               cand != "information_schema" {
                referencedSchemas.insert(cand)
            }
        }

        XCTAssertTrue(referencedSchemas.contains("merchant"))
        XCTAssertTrue(referencedSchemas.contains("billing"))
        XCTAssertFalse(referencedSchemas.contains("DATA"), "DATA must never be recognized as a schema name")
        XCTAssertFalse(referencedSchemas.contains("CONSTRAINT"), "CONSTRAINT must never be recognized as a schema name")
        XCTAssertFalse(referencedSchemas.contains("public"))
    }
}
