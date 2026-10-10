---
name: postgrace-qa
description: >-
  Expert Quality Assurance (QA) workflow and test automation for Postgrace native macOS app.
  Use when testing Postgrace, running unit and integration test suites, verifying database
  operations (PostgreSQL & MySQL), inspecting Swift compilation, verifying SQL safety rules,
  validating macOS UI activation/focus, or generating comprehensive QA reports.
---

# Postgrace Quality Assurance (QA) Playbook

This skill defines the verified QA workflows, test automation procedures, regression test matrix, and reporting standards for **Postgrace** (native macOS PostgreSQL and MySQL/MariaDB client).

---

## 1. Quick Test Run

To execute the entire automated test suite:

```bash
swift test
```

> **Note on macOS Sandbox**: In restricted sandbox environments, Swift test execution may require sandbox bypass (`BypassSandbox: true`) due to Apple Clang module cache writes (`/var/folders/.../clang/ModuleCache`).

To run a specific test suite or test case:

```bash
# Run only SQL Safety Analyzer tests
swift test --filter SQLSafetyAnalyzerTests

# Run only Data Transfer tests
swift test --filter DataTransferTests

# Run only ViewModel tests
swift test --filter ViewModelTests
```

---

## 2. Testing Tiers & Coverage

| Tier | Target Suites | Key Verification Areas |
|:---|:---|:---|
| **Tier 1: Static Verification** | Compiler & Linters | `swift build -c release -Xswiftc -warnings-as-errors` — 0 warnings, 0 errors, strict concurrency compliance |
| **Tier 2: Models & Core Logic** | `ModelTests`, `SQLFormatterTests` | `CellValue` parsing & formatting (`NULL`, `Int`, `Double`, `Bool`, `JSON`, `Array`), `SavedConnection` serialization, SQL beautification and comment preservation |
| **Tier 3: Safety & Risk Analysis** | `SQLSafetyAnalyzerTests` | Risk tier classifications (`SAFE`, `ELEVATED`, `CRITICAL`), detection of unbounded `UPDATE`/`DELETE`, `TRUNCATE`, `DROP`, string literal escaping, CTE detection |
| **Tier 4: State & ViewModels** | `ViewModelTests` | Tab lifecycle & query isolation, `DataGridViewModel` pagination math and filter predicates, `ConnectionViewModel` CRUD, safe-mode toggling, database role resolution |
| **Tier 5: Data Transfer & Serialization** | `DataTransferTests` | CSV stream chunking, RFC 4180 delimiter escaping, JSON array import/export, batch transaction rollback on error |
| **Tier 6: Live Wire Protocol Integration** | `PostgresIntegrationTests` | PostgreSQL 14–18+ wire protocol handshakes, SCRAM-SHA-256 auth, live database switching (`current_database()`), schema introspection catalogs (`pg_database`, `pg_namespace`, `pg_class`) |

---

## 3. Pre-Release QA Verification Checklist

Before releasing any build or merging significant features:

1. **Compilation Check**:
   - Ensure clean compilation without warnings.
   - Verify all closures and guard statements conform to Swift 5.9+ grammar.
2. **Automated Test Run**:
   - Execute all 75+ automated test cases.
   - Ensure 100% pass rate.
3. **macOS Window & Focus Integration**:
   - Verify `NSApplicationDelegate` sets `activationPolicy(.regular)` and `activate(ignoringOtherApps: true)`.
   - Ensure window attains key window status (`isKeyWindow == true`) so AppKit routes keyboard events properly.
   - Verify `@FocusState` in `ConnectionFormView` and `QueryEditorView`.
4. **Database Engine Agnosticism**:
   - For any schema or query change, verify behavior against both PostgreSQL and MySQL/MariaDB dialect handlers (`DatabaseDriverProtocol`).
5. **Credential Safety & Keychain**:
   - Passwords must never be logged or stored in plain-text configurations.
   - Verify password masking in UI and persistence via `KeychainService`.

---

## 4. Generating QA Reports

After executing a test cycle, document the findings matching the schema in `QA_REPORT.md`:

- **Executive Summary**: Pass/fail rate, execution time, target platform, database versions.
- **Defects Identified & Resolved**: Root cause analysis, code diff, and verification test case.
- **Test Suite Breakdown Table**: Suite name, test count, duration, and pass status.
- **Recommendations for Next Milestones**: Performance benchmarks, entitlement checks, or pending edge cases.

---

## 5. Automated QA Runner Script

You can run the bundled QA runner script:

```bash
.agents/skills/postgrace-qa/scripts/run_qa_suite.sh
```
