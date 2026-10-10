import XCTest
import MySQLNIO
@testable import Postgrace

final class MySQLDriverUnitTests: XCTestCase {

    func testMySQLDriverFormatErrorSpecificCases() {
        // Duplicate Entry
        let dupErr = MySQLError.duplicateEntry("Key (email)=(alice@example.com) already exists")
        let dupFormatted = MySQLDriver.formatError(dupErr)
        XCTAssertTrue(dupFormatted.contains("Duplicate entry:"))

        // Invalid Syntax
        let syntaxErr = MySQLError.invalidSyntax("Near 'SELEC *'")
        let syntaxFormatted = MySQLDriver.formatError(syntaxErr)
        XCTAssertTrue(syntaxFormatted.contains("Syntax error:"))

        // Secure Connection Required
        let secErr = MySQLError.secureConnectionRequired
        let secFormatted = MySQLDriver.formatError(secErr)
        XCTAssertTrue(secFormatted.contains("secure TLS connection is required"))

        // Connection Closed
        let closedErr = MySQLError.closed
        let closedFormatted = MySQLDriver.formatError(closedErr)
        XCTAssertTrue(closedFormatted.contains("connection was closed"))
    }

    func testMySQLDriverFormatErrorNetworkAndSystemErrors() {
        struct MockError: Error, CustomStringConvertible {
            let description: String
        }

        // Connection Refused
        let refusedErr = MockError(description: "connect failed: Connection refused (errno: 61)")
        let refusedFormatted = MySQLDriver.formatError(refusedErr, host: "127.0.0.1", port: 3306)
        XCTAssertTrue(refusedFormatted.contains("Connection refused (127.0.0.1:3306)"))
        XCTAssertTrue(refusedFormatted.contains("port 3306"))

        // Connection Timed Out
        let timeoutErr = MockError(description: "operation timed out (errno: 60)")
        let timeoutFormatted = MySQLDriver.formatError(timeoutErr, host: "10.0.0.1", port: 3306)
        XCTAssertTrue(timeoutFormatted.contains("Connection timed out (10.0.0.1:3306)"))

        // Access Denied (1045)
        let authErr = MockError(description: "Access denied for user 'root'@'localhost' (using password: YES)")
        let authFormatted = MySQLDriver.formatError(authErr)
        XCTAssertTrue(authFormatted.contains("Access denied for user"))

        // Unknown Database (1049)
        let dbErr = MockError(description: "Unknown database 'missing_catalog'")
        let dbFormatted = MySQLDriver.formatError(dbErr)
        XCTAssertTrue(dbFormatted.contains("Unknown database"))
    }

    func testDatabaseServiceFormatErrorDelegation() {
        let mysqlDup = MySQLError.duplicateEntry("test key")
        let formatted = DatabaseService.formatError(mysqlDup)
        XCTAssertTrue(formatted.contains("Duplicate entry:"))

        let customErr = DatabaseServiceError.connectionFailed("Custom failure reason")
        let serviceFormatted = DatabaseService.formatError(customErr)
        XCTAssertEqual(serviceFormatted, "Connection failed: Custom failure reason")
    }

    func testMySQLDriverInitialState() async {
        let driver = MySQLDriver(engine: .mysql)
        let isConn = await driver.isConnected
        let currDb = await driver.currentDatabase
        let activeCfg = await driver.activeConfig
        let activePw = await driver.activePassword
        let lastErr = await driver.lastConnectionError
        let eng = await driver.engine

        XCTAssertFalse(isConn)
        XCTAssertNil(currDb)
        XCTAssertNil(activeCfg)
        XCTAssertNil(activePw)
        XCTAssertNil(lastErr)
        XCTAssertEqual(eng, .mysql)
    }
}
