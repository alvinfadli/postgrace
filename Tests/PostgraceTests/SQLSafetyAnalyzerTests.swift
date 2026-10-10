import XCTest
@testable import Postgrace

final class SQLSafetyAnalyzerTests: XCTestCase {

    // MARK: - Read-Only Statements

    func testReadOnlySelectStatements() {
        let q1 = "SELECT * FROM users;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertFalse(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "SELECT")
        XCTAssertFalse(r1.isUnbounded)

        let q2 = "   select id, name from public.users where active = true order by id desc limit 50;  "
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertFalse(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "SELECT")

        let q3 = "-- check users\nSELECT count(*) FROM subscriptions;"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertFalse(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "SELECT")

        let q4 = "/* block comment */ SELECT 1;"
        let r4 = SQLSafetyAnalyzer.analyze(q4)
        XCTAssertFalse(r4.isDangerous)
        XCTAssertEqual(r4.statementType, "SELECT")
    }

    func testExplainAndShowStatements() {
        let q1 = "EXPLAIN ANALYZE SELECT * FROM users;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertFalse(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "EXPLAIN")

        let q2 = "SHOW server_version;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertFalse(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "SHOW")

        let q3 = "SHOW ALL;"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertFalse(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "SHOW")
    }

    func testCommonTableExpressions() {
        // Pure read-only CTE
        let q1 = """
        WITH active_users AS (
            SELECT * FROM users WHERE active = true
        )
        SELECT * FROM active_users;
        """
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertFalse(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "SELECT")

        // Mutating CTE with DELETE
        let q2 = """
        WITH deleted_rows AS (
            DELETE FROM audit_logs RETURNING *
        )
        SELECT count(*) FROM deleted_rows;
        """
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "WITH DELETE")

        // Mutating CTE with INSERT
        let q3 = """
        WITH inserted_rows AS (
            INSERT INTO audit_logs (msg) VALUES ('test') RETURNING *
        )
        SELECT * FROM inserted_rows;
        """
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertTrue(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "WITH INSERT")
    }

    // MARK: - Destructive Unbounded Mutations (TC-01, TC-04)

    func testUnboundedDelete() {
        let q1 = "DELETE FROM users;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "DELETE")
        XCTAssertTrue(r1.isUnbounded)
        XCTAssertEqual(r1.targetObject, "users")

        let q2 = "DELETE FROM \"tenant_app\".\"users\";"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertTrue(r2.isUnbounded)
        XCTAssertEqual(r2.targetObject, "tenant_app.users")

        let q3 = "-- delete all\nDELETE FROM accounts"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertTrue(r3.isDangerous)
        XCTAssertTrue(r3.isUnbounded)
        XCTAssertEqual(r3.targetObject, "accounts")
    }

    func testBoundedDelete() {
        let q1 = "DELETE FROM users WHERE id = 42;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "DELETE")
        XCTAssertFalse(r1.isUnbounded)
        XCTAssertEqual(r1.targetObject, "users")
    }

    func testUnboundedUpdate() {
        let q1 = "UPDATE users SET active = false;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "UPDATE")
        XCTAssertTrue(r1.isUnbounded)
        XCTAssertEqual(r1.targetObject, "users")

        // String literal contains 'WHERE' keyword - should still be detected as UNBOUNDED!
        let q2 = "UPDATE users SET status = 'WHERE';"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertTrue(r2.isUnbounded)
        XCTAssertEqual(r2.targetObject, "users")

        // Subquery contains WHERE, but the outer UPDATE is unbounded!
        let q3 = "UPDATE users SET active = (SELECT true WHERE 1 = 1);"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertTrue(r3.isDangerous)
        XCTAssertTrue(r3.isUnbounded)
        XCTAssertEqual(r3.targetObject, "users")
    }

    func testBoundedUpdate() {
        let q1 = "UPDATE users SET active = false WHERE id = 10;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "UPDATE")
        XCTAssertFalse(r1.isUnbounded)
        XCTAssertEqual(r1.targetObject, "users")
    }

    // MARK: - Destructive DDL (TC-02, TC-05)

    func testDropStatements() {
        let q1 = "DROP TABLE payments;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "DROP")
        XCTAssertEqual(r1.targetObject, "payments")

        let q2 = "DROP DATABASE production;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "DROP")
        XCTAssertEqual(r2.targetObject, "production")

        let q3 = "DROP SCHEMA IF EXISTS analytics CASCADE;"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertTrue(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "DROP")
        XCTAssertEqual(r3.targetObject, "analytics")
    }

    func testTruncateStatements() {
        let q1 = "TRUNCATE TABLE logs;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "TRUNCATE")
        XCTAssertEqual(r1.targetObject, "logs")

        let q2 = "TRUNCATE subscriptions RESTART IDENTITY;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "TRUNCATE")
        XCTAssertEqual(r2.targetObject, "subscriptions")
    }

    // MARK: - Structural DDL & Other Mutations

    func testAlterStatements() {
        let q1 = "ALTER TABLE users DROP COLUMN phone;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "ALTER")
        XCTAssertEqual(r1.targetObject, "users")

        let q2 = "ALTER TABLE users ADD COLUMN phone text;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "ALTER")
        XCTAssertEqual(r2.targetObject, "users")
    }

    func testCreateStatements() {
        let q1 = "CREATE TABLE new_table (id serial primary key, name text);"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "CREATE")
        XCTAssertEqual(r1.targetObject, "new_table")

        let q2 = "CREATE INDEX idx_user_email ON users(email);"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "CREATE")
    }

    func testInsertAndMerge() {
        let q1 = "INSERT INTO users (name, email) VALUES ('Alice', 'alice@test.com');"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "INSERT")
        XCTAssertEqual(r1.targetObject, "users")

        let q2 = "MERGE INTO target_table USING source_table ON target_table.id = source_table.id WHEN MATCHED THEN DELETE;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "MERGE")
        XCTAssertEqual(r2.targetObject, "target_table")
    }

    func testSelectInto() {
        let q = "SELECT * INTO new_table FROM old_table;"
        let r = SQLSafetyAnalyzer.analyze(q)
        XCTAssertTrue(r.isDangerous)
        XCTAssertEqual(r.statementType, "SELECT INTO")
        XCTAssertEqual(r.targetObject, "new_table")
    }

    func testGrantRevokeDoVacuum() {
        let q1 = "GRANT ALL PRIVILEGES ON users TO app_user;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "GRANT")

        let q2 = "REVOKE CONNECT ON DATABASE prod FROM public;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "REVOKE")

        let q3 = "DO $$ BEGIN RAISE NOTICE 'hi'; END $$;"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertTrue(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "DO")

        let q4 = "VACUUM FULL users;"
        let r4 = SQLSafetyAnalyzer.analyze(q4)
        XCTAssertTrue(r4.isDangerous)
        XCTAssertEqual(r4.statementType, "VACUUM FULL")

        let q5 = "VACUUM users;"
        let r5 = SQLSafetyAnalyzer.analyze(q5)
        XCTAssertFalse(r5.isDangerous)
        XCTAssertEqual(r5.statementType, "VACUUM")
    }

    // MARK: - Multi-Statement / Batch Scripts

    func testBatchStatements() {
        let q1 = "SELECT 1; DROP TABLE users;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "BATCH")

        let q2 = "SELECT 1; SELECT 2;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "BATCH")
    }

    // MARK: - Edge Cases & Literals

    func testKeywordsInsideStringLiteralsAreNotTreatedAsMutations() {
        let q = "SELECT 'DROP TABLE users' AS sql_statement;"
        let r = SQLSafetyAnalyzer.analyze(q)
        XCTAssertFalse(r.isDangerous)
        XCTAssertEqual(r.statementType, "SELECT")
    }

    func testEmptyStatements() {
        let r1 = SQLSafetyAnalyzer.analyze("")
        XCTAssertFalse(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "EMPTY")

        let r2 = SQLSafetyAnalyzer.analyze("   \n\t  ")
        XCTAssertFalse(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "EMPTY")
    }

    // MARK: - MySQL & MariaDB Dialect Safety

    func testMySQLDialectSafety() {
        // Backtick quoted identifiers with unbounded DELETE
        let q1 = "DELETE FROM `ecommerce`.`customers`;"
        let r1 = SQLSafetyAnalyzer.analyze(q1)
        XCTAssertTrue(r1.isDangerous)
        XCTAssertEqual(r1.statementType, "DELETE")
        XCTAssertTrue(r1.isUnbounded)
        XCTAssertEqual(r1.targetObject, "ecommerce.customers")

        // Backtick bounded UPDATE
        let q2 = "UPDATE `orders` SET `status` = 'shipped' WHERE `id` = 42;"
        let r2 = SQLSafetyAnalyzer.analyze(q2)
        XCTAssertTrue(r2.isDangerous)
        XCTAssertEqual(r2.statementType, "UPDATE")
        XCTAssertFalse(r2.isUnbounded)
        XCTAssertEqual(r2.targetObject, "orders")

        // Backtick SELECT
        let q3 = "SELECT `id`, `name` FROM `users` WHERE `active` = 1;"
        let r3 = SQLSafetyAnalyzer.analyze(q3)
        XCTAssertFalse(r3.isDangerous)
        XCTAssertEqual(r3.statementType, "SELECT")

        // MySQL hash comment
        let q4 = "# MySQL style hash comment\nSELECT * FROM `inventory`;"
        let r4 = SQLSafetyAnalyzer.analyze(q4)
        XCTAssertFalse(r4.isDangerous)
        XCTAssertEqual(r4.statementType, "SELECT")

        // MySQL DROP TABLE
        let q5 = "DROP TABLE IF EXISTS `legacy_logs`;"
        let r5 = SQLSafetyAnalyzer.analyze(q5)
        XCTAssertTrue(r5.isDangerous)
        XCTAssertEqual(r5.statementType, "DROP")
        XCTAssertEqual(r5.targetObject, "legacy_logs")
    }
}
