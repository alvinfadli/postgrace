# Business Requirements Document (BRD)
## Project: Database & Schema Export System for Postgrace (PostgreSQL & Multi-Engine)
**Document Version:** 1.0.0  
**Status:** In Review / Ready for Approval  
**Owner:** Product & Engineering  
**Target Release:** Postgrace v2.2 (Data Portability & Toolchain Integration)  
**Date:** October 8, 2026  

---

## 1. Executive Summary

### 1.1 Context & Background
Postgrace is a native, lightweight macOS database studio engineered with Swift and SwiftUI, delivering sub-second startup times, memory efficiency (<50 MB baseline), and strict adherence to Apple’s Human Interface Guidelines (macOS HIG). A central pillar of database management workflows is **Data Portability**: exporting database structures and tabular datasets for backups, environment migrations (production to staging/local), CI/CD seed data, schema versioning, and offline analytical reporting.

Unlike flat database architectures (such as MySQL or SQLite where `DATABASE` and `SCHEMA` are largely synonymous), PostgreSQL implements a strict, multi-tiered hierarchy:
$$\text{Cluster (Server Instance)} \longrightarrow \text{Database} \longrightarrow \text{Schema (Namespace)} \longrightarrow \text{Relations (Tables, Views, Types, Sequences)}$$

Exporting databases and schemas in PostgreSQL introduces complex namespace isolation, custom data type ordering, cross-schema foreign key dependencies, sequence state tracking, and toolchain dependencies (`pg_dump` binary execution vs. native Swift NIO fallback).

### 1.2 Problem Statement
1. **Inconsistent Schema Isolation:** Many database clients treat schema export as merely dumping a set of tables, neglecting PostgreSQL-specific requirements such as `CREATE SCHEMA IF NOT EXISTS`, schema-scoped `search_path` controls, custom composite types (`CREATE TYPE`), and sequence current-value offsets (`setval`).
2. **Missing System Schema Filtration:** Unfiltered database dumps frequently attempt to introspect and export internal system catalogs (`pg_catalog`, `information_schema`, `pg_toast`, extension schemas), leading to permission errors or bloated dump files.
3. **Circular Foreign Key & Cross-Schema Fragility:** When exporting an isolated schema that references tables in another schema, restores often fail catastrophically due to missing constraints or unhandled topological ordering.
4. **Toolchain Dependency Fragility:** Clients that exclusively rely on external binaries (`pg_dump`) fail completely if the binary is absent on the user's macOS system. Conversely, clients that rely exclusively on custom SQL queries fail on complex binary archives or multi-gigabyte production dumps.
5. **Memory Spikes on Large Datasets:** Non-buffered exports buffer large result sets in memory, crashing or freezing the macOS application during multi-gigabyte table exports.

### 1.3 Solution Overview
Implement a resilient, dual-engine **Database & Schema Export System** in Postgrace:
* **PostgreSQL-Native Schema Engine:** Accurately dumps namespaces, topological DDL (Enums/Types $\rightarrow$ Sequences $\rightarrow$ Tables $\rightarrow$ Data $\rightarrow$ Constraints $\rightarrow$ Views/Functions $\rightarrow$ Triggers), and sequence synchronization (`setval`).
* **Flexible Export Scopes:** Full Database, Multi-Schema, Single Schema, Multi-Table, and Single Table.
* **Dual-Engine Execution Pipeline:** 
  1. *Primary:* PostgreSQL CLI Toolchain (`pg_dump`) supporting custom compressed binary archives (`-Fc`) and plain text SQL (`-Fp`).
  2. *Fallback:* Native in-memory streaming Swift NIO engine using chunked 64 KB buffered file streams when CLI binaries are unavailable.
* **Modern macOS UI:** Integrated Export Sheet with scope previews, granular schema/table checklists, content mode toggles (Structure & Data, Structure Only, Data Only), and real-time progress indicators.
* **Safe Mode & SSH Tunnel Integration:** Seamless execution across remote bastion hosts and high-risk production environment protections.

---

## 2. Business Objectives & Success Metrics

### 2.1 Strategic Business Goals
* **Complete Data Portability:** Enable developers and DBAs to generate production-grade PostgreSQL dumps and schema backups directly within Postgrace without opening a terminal.
* **Zero CLI Prerequisite Barrier:** Guarantee that users without Homebrew or local PostgreSQL CLI tools can still export clean DDL and table data via native Swift streaming.
* **High-Performance Stability:** Export multi-gigabyte tables without memory leaks, maintaining app memory under 75 MB throughout the process.
* **Seamless Multi-Engine Consistency:** Establish a unified export interface that gracefully handles PostgreSQL namespaces today and easily extends to MySQL/MariaDB database exports.

### 2.2 Key Performance Indicators (KPIs)
| Metric | Baseline (Current) | Target (v2.2) | Verification Method |
| :--- | :--- | :--- | :--- |
| **Toolchain Independence** | Fails without `pg_dump` | 100% successful native fallback | Export on clean macOS machine without `libpq` |
| **Export Latency Overhead** | N/A | $\le 5\%$ variance vs. raw CLI `pg_dump` | Benchmark against CLI on 1M rows table |
| **Memory Footprint During Dump** | Spikes > 500 MB | Flat baseline ($< 75\text{ MB}$) via 64 KB buffers | Instruments Activity Monitor trace |
| **Cross-Schema Restore Rate** | ~70% (FK failures) | 100% clean restore with 2-pass DDL | Automated dump-and-restore test harness |
| **Cancellation Responsiveness** | UI hang | $< 250\text{ ms}$ clean abort and file cleanup | User cancellation stress tests |

---

## 3. User Personas & Use Cases

### 3.1 Target Personas
1. **Backend Engineer (Alex):**
   - *Scenario:* Needs to dump the structure (DDL only) of the `billing` and `auth` schemas to check into Git or spin up a local Docker test environment.
   - *Requirement:* Wants "Structure Only" export generating clean `CREATE SCHEMA`, `CREATE TYPE`, and `CREATE TABLE` statements with zero data rows.
2. **DevOps / Cloud Administrator (Brenda):**
   - *Scenario:* Connected via an SSH tunnel to an AWS RDS PostgreSQL instance; needs a full binary compressed database dump (`.dump`) before running schema migrations.
   - *Requirement:* Needs `pg_dump -Fc` with `--clean --if-exists` options routed seamlessly through the active SSH tunnel.
3. **Data Analyst / BI Specialist (Carlos):**
   - *Scenario:* Needs to extract data from 4 reporting tables across two schemas into CSV or JSON formats for analysis in Excel or Python.
   - *Requirement:* Needs multi-table batch export packaged into a clean `.zip` archive or directory.

### 3.2 High-Value User Stories
* **US-01:** *As a developer, I want to export an entire database so that I have a complete backup of all user schemas and tables.*
* **US-02:** *As a developer, I want to export only one specific schema (`public` or `audit`) so that I can migrate just that namespace to another database.*
* **US-03:** *As a developer, I want to export "Structure Only" so that I can extract clean DDL without sensitive user data.*
* **US-04:** *As a developer, I want PostgreSQL custom binary dumps (`.dump`) for fast parallel `pg_restore` compatibility.*
* **US-05:** *As a developer on a fresh Mac without PostgreSQL installed, I want Postgrace to seamlessly fallback to native streaming export without erroring.*

---

## 4. Scope of Work

### 4.1 In-Scope
* **Export Scopes:**
  * Full Database (`Database: <name>`)
  * Multiple Schemas (`Schemas (<N> selected)`)
  * Single Schema (`Schema: <name>`)
  * Multiple Tables (`Tables (<N> selected)`)
  * Single Table (`<schema>.<table>`)
* **PostgreSQL-Specific Schema Handling:**
  * Auto-exclusion of system schemas (`pg_catalog`, `information_schema`, `pg_toast`, etc.).
  * Generation of `CREATE SCHEMA IF NOT EXISTS "schema_name";`.
  * Proper namespace isolation via `SET search_path = "schema_name", pg_catalog;`.
  * Topological DDL ordering: Enums/Types $\rightarrow$ Sequences $\rightarrow$ Tables $\rightarrow$ Data $\rightarrow$ Constraints/FKs $\rightarrow$ Views $\rightarrow$ Triggers.
  * Identity column and sequence synchronization using `SELECT setval(...)`.
  * Cross-schema foreign key handling (inclusion vs. isolation option).
* **Export Content Modes:**
  * Structure and Data (Full DDL + INSERTs/COPY)
  * Structure Only (DDL statements only)
  * Data Only (Data rows only)
* **Output Formats:**
  * PostgreSQL Custom Dump (`.dump`, binary compressed `-Fc`)
  * Plain SQL Script (`.sql`, human-readable `-Fp`)
  * CSV (Single table or multi-table ZIP archive)
  * JSON (Standard array or NDJSON)
* **Execution Engines:**
  * CLI Toolchain execution via `PostgresToolchainService` (`pg_dump`).
  * Native Swift streaming fallback via `PostgresNIO` and buffered file handles.
  * Tunnel routing for remote SSH connections.
* **UI & Workflows:**
  * Native macOS Export Sheet with real-time configuration.
  * Schema & Table selection tree with quick filters.
  * Progress sheet with transferred byte counts, row counts, and cancellation.

### 4.2 Out-of-Scope (Future Phases)
* Automated scheduled background exports (cron / recurring backups).
* Direct cloud-storage upload (e.g., uploading dumps directly to Amazon S3 or Google Cloud Storage).
* Logical replication stream decoding.

---

## 5. PostgreSQL Schema & Database Export Specifications

### 5.1 Architecture Hierarchy Comparison

```
+----------------------------------------------------------------------------------------------------+
|                                    RDBMS HIERARCHY COMPARISON                                      |
+---------------------------------------------------+------------------------------------------------+
| PostgreSQL Architectural Model                    | MySQL / MariaDB Architectural Model            |
+---------------------------------------------------+------------------------------------------------+
| Instance / Cluster (Port 5432)                    | Instance / Server (Port 3306)                  |
|   └── Database A (Catalog Isolation)              |   └── Database / Schema A (Synonymous)         |
|         ├── Schema: "public"                      |         ├── Table: users                       |
|         │     ├── Table: users                    |         └── Table: orders                      |
|         │     └── Sequence: users_id_seq          |   └── Database / Schema B                      |
|         ├── Schema: "audit"                       |         └── Table: log_events                  |
|         │     └── Table: events                   |                                                |
|         └── System Schemas (Excluded by Default)  |                                                |
|               ├── pg_catalog                      |                                                |
|               └── information_schema              |                                                |
+---------------------------------------------------+------------------------------------------------+
```

---

### 5.2 PostgreSQL System Schema Filtration Rules

When exporting at the Database level, Postgrace must strictly filter out internal system namespaces to avoid permission errors and catalog pollution:

```sql
-- Query to identify eligible user schemas in PostgreSQL:
SELECT nspname 
FROM pg_namespace 
WHERE nspname NOT LIKE 'pg_%' 
  AND nspname != 'information_schema'
ORDER BY nspname ASC;
```

**Filtration Table:**
| Schema Pattern | Type | Default Export Behavior | Rationale |
| :--- | :--- | :--- | :--- |
| `pg_catalog` | Core System Catalog | **Excluded** | Internal system metadata; cannot be recreated. |
| `information_schema` | ANSI Standard Catalog | **Excluded** | Read-only SQL standard views over internal catalogs. |
| `pg_toast*` | TOAST Storage | **Excluded** | Managed automatically by storage engine for out-of-line data. |
| `pg_temp*` / `pg_toast_temp*` | Session Temp Schemas | **Excluded** | Transient tables tied to active backend sessions. |
| User Schemas (`public`, `audit`, etc.) | User Namespaces | **Included** | Target of user backup and migration. |

---

### 5.3 PostgreSQL DDL Topological Ordering Matrix

To prevent dependency deadlocks during dump restoration, Postgrace enforces the following two-pass ordering:

```
+----------------------------------------------------------------------------------------------------+
|                                  TOPOLOGICAL DDL DUMP ORDER                                        |
+-------+--------------------------------+-----------------------------------------------------------+
| Stage | Object Type                    | Description & SQL Example                                 |
+-------+--------------------------------+-----------------------------------------------------------+
| 01    | Schema Declaration             | CREATE SCHEMA IF NOT EXISTS "audit";                      |
| 02    | Search Path Setup              | SET search_path = "audit", pg_catalog;                    |
| 03    | Extensions (Optional)          | CREATE EXTENSION IF NOT EXISTS "uuid-ossp";               |
| 04    | Custom Types & ENUMs           | CREATE TYPE "audit"."severity_level" AS ENUM ('LOW','HI');|
| 05    | Sequences                      | CREATE SEQUENCE "audit"."event_seq";                      |
| 06    | Base Tables (Structure Only)   | CREATE TABLE "audit"."events" (...);                      |
| 07    | Data Loading (INSERT / COPY)   | COPY "audit"."events" FROM stdin; / INSERT INTO ...       |
| 08    | Sequence Synchronization       | SELECT setval('"audit"."event_seq"', (SELECT max(id)...));|
| 09    | Primary Keys & Unique Indexes  | ALTER TABLE "audit"."events" ADD PRIMARY KEY (id);        |
| 10    | Foreign Key Constraints        | ALTER TABLE "audit"."events" ADD CONSTRAINT fk_user...    |
| 11    | Standard & Materialized Views  | CREATE VIEW / CREATE MATERIALIZED VIEW ...                |
| 12    | Stored Functions & Procedures  | CREATE OR REPLACE FUNCTION ...                            |
| 13    | Triggers                       | CREATE TRIGGER trg_audit_log AFTER INSERT ...             |
+-------+--------------------------------+-----------------------------------------------------------+
```

---

### 5.4 Cross-Schema Foreign Key Dependency Handling

In complex PostgreSQL databases, a table in `audit` may reference a table in `public`:
`"audit"."events".user_id` $\longrightarrow$ `"public"."users".id`

**Resolution Workflow in Postgrace:**
1. **Full Database Export:** All schemas are contained in the dump. Foreign keys are placed in Stage 10 (after all tables in all schemas are populated with data), guaranteeing zero dependency errors.
2. **Single Schema Export:**
   - Postgrace inspects foreign key definitions in `pg_constraint`.
   - If an external schema reference is detected, Postgrace provides a user toggle:
     - **Option A (Include External FKs - Default):** Retains foreign key constraint. Suitable when restoring into an existing target database that already contains `"public"."users"`.
     - **Option B (Isolate / Strip External FKs):** Comments out external foreign key constraints in the output SQL, logging a gentle warning in the export header. Suitable for testing the schema in complete isolation.

---

## 6. Execution Pipeline: Dual-Engine Strategy

```
                                  +------------------------------------+
                                  |      Export Task Dispatched        |
                                  +------------------------------------+
                                                    |
                                                    v
                                  +------------------------------------+
                                  | Is Toolchain (pg_dump) Available?  |
                                  +------------------------------------+
                                           /                  \
                                     YES  /                    \  NO
                                         v                      v
                       +-----------------------+     +-----------------------+
                       |   Toolchain Engine    |     | Native Swift Engine   |
                       |       (pg_dump)       |     |     (PostgresNIO)     |
                       +-----------------------+     +-----------------------+
                                   |                             |
                       +-----------------------+     +-----------------------+
                       | - Shell Process       |     | - In-memory Query     |
                       | - Binary .dump (-Fc)  |     | - 64 KB Buffered File |
                       | - Native parallelism  |     | - Topological DDL SQL |
                       | - Streaming log pipe  |     | - CSV / JSON / SQL    |
                       +-----------------------+     +-----------------------+
                                   \                             /
                                    \                           /
                                     v                         v
                                  +------------------------------------+
                                  |   Progress Callback & Completion   |
                                  +------------------------------------+
```

### 6.1 Toolchain Engine (`PostgresToolchainService`)
When `pg_dump` is discovered in standard macOS paths (`/opt/homebrew/bin/pg_dump`, `/usr/local/bin/pg_dump`, `/Applications/Postgres.app/...`, or system `PATH`):
* Postgrace spawns an asynchronous `Process` instance with piped stdout/stderr.
* **Security:** Master passwords are never passed as cleartext CLI arguments. Postgrace injects credentials securely via environment variables (`PGPASSWORD`) or a temporary secure `.pgpass` file with `0600` POSIX permissions.
* **SSH Tunnel Routing:** If the active connection uses an SSH tunnel, `pg_dump` connects to `127.0.0.1:<local_tunnel_port>`.

**Command Argument Mapping:**
| Export Scope | Generated `pg_dump` Flags |
| :--- | :--- |
| **Full Database** | `pg_dump -h <host> -p <port> -U <user> -d <database> -F <c\|p> -f <path>` |
| **Single Schema** | `pg_dump ... -d <database> -n "<schema>" -F <c\|p> -f <path>` |
| **Multiple Schemas** | `pg_dump ... -d <database> -n "<schema1>" -n "<schema2>" -F <c\|p> -f <path>` |
| **Multiple Tables** | `pg_dump ... -d <database> -t "<schema1>.<table1>" -t "<schema2>.<table2>" ...` |
| **Structure Only** | Appends `--schema-only` |
| **Data Only** | Appends `--data-only` |
| **Clean on Restore** | Appends `--clean --if-exists` |

---

### 6.2 Native Swift Streaming Engine (`ExportService`)
When `pg_dump` is not installed on macOS:
* Postgrace switches automatically to its native Swift NIO query and streaming subsystem.
* Memory management uses a dedicated `BufferedFileHandle` with a **64 KB buffer threshold**, flushing chunks to disk immediately to prevent memory ballooning.
* Introspects DDL from `information_schema` and `pg_catalog` (columns, constraints, types, defaults, indexes).
* Streams rows using chunked cursor reads or `PostgresNIO` row streaming callbacks.
* Emits standard, fully compliant PostgreSQL SQL files or multi-file ZIP archives.

---

## 7. User Interface & Workflow Design

### 7.1 Export Modal Sheet Layout

```
+--------------------------------------------------------------------------------------------------+
| Export Data                                                                                  [X] |
| Scope: Database 'production_db'                                                                  |
+--------------------------------------------------------------------------------------------------+
| EXPORT CONTENT                                                                                   |
| [ Structure and Data ]      [ Structure Only (DDL) ]      [ Data Only ]                          |
| "Exports table definitions (CREATE TABLE DDL) and row records."                                  |
|--------------------------------------------------------------------------------------------------|
| EXPORT FORMAT                                                                                    |
| [ SQL Script (.sql) ]   [ PostgreSQL Dump (.dump) ]   [ CSV (.zip) ]   [ JSON (.json) ]           |
| "Binary compressed archive (pg_dump -Fc) supporting fast parallel restore."                      |
|--------------------------------------------------------------------------------------------------|
| INCLUDED SCHEMAS & TABLES                                                                        |
| [ Search schemas and tables...                                           ]                       |
| [x] public (18 tables)                                                    [ Select All | None ]  |
|     [x] users                                                                                    |
|     [x] orders                                                                                   |
|     [x] products                                                                                 |
| [x] billing (4 tables)                                                                           |
| [ ] audit (Exclude from backup)                                                                  |
|--------------------------------------------------------------------------------------------------|
| ADVANCED OPTIONS                                                                                 |
| [x] Clean before restore (DROP ... IF EXISTS)                                                    |
| [x] Wrap in single transaction (BEGIN ... COMMIT)                                                |
| [ ] Include external cross-schema foreign keys                                                   |
|--------------------------------------------------------------------------------------------------|
| Target Destination: ~/Downloads/production_db_20261008_100000.dump               [ Browse... ]  |
|                                                                                                  |
| [Cancel]                                                                         [ Export Data ] |
+--------------------------------------------------------------------------------------------------+
```

### 7.2 Progress & Status Modal

```
+--------------------------------------------------------------------------------------------------+
| Exporting Database 'production_db'...                                                            |
|                                                                                                  |
| [=======================================>                                ] 64%                   |
| Dumping schema 'public', table 'orders' (Row 42,000 of ~65,000)...                               |
|                                                                                                  |
| Data Transferred: 14.8 MB  •  Elapsed: 00:12  •  Speed: 1.2 MB/s                                 |
|                                                                                                  |
| [Cancel Export]                                                                                  |
+--------------------------------------------------------------------------------------------------+
```

---

## 8. Technical Architecture & Component Models

### 8.1 Enhanced `ExportScope` and `ExportConfiguration`

```swift
import Foundation

/// Defines the scope of the export operation.
public enum ExportScope: Equatable, Hashable, Sendable {
    case database(name: String)
    case multipleSchemas(names: [String])
    case schema(name: String, tables: [String] = [])
    case multipleTables(items: [ExportTableItem])
    case table(schema: String, table: String)

    public var title: String {
        switch self {
        case .database(let name):
            return "Database: \(name)"
        case .multipleSchemas(let names):
            return "Schemas (\(names.count) selected)"
        case .schema(let name, _):
            return "Schema: \(name)"
        case .multipleTables(let items):
            return items.count == 1 ? "\(items[0].schema).\(items[0].table)" : "Tables (\(items.count) selected)"
        case .table(let schema, let table):
            return "\(schema).\(table)"
        }
    }
}

/// Advanced options specifically for PostgreSQL exports.
public struct PostgresExportOptions: Equatable, Sendable {
    public var includeSchemaCreate: Bool = true
    public var setPathHeader: Bool = true
    public var cleanBeforeRestore: Bool = true
    public var singleTransaction: Bool = true
    public var includeExternalForeignKeys: Bool = true
    public var customDumpCompressionLevel: Int = 6 // 1-9
    public var excludedSchemas: Set<String> = []

    public init() {}
}
```

### 8.2 Safe Mode & High-Risk Guardrails
* Exporting databases does not modify server state; however, in environments marked as **Production** (Red Environment Tag), Postgrace logs all export triggers to prevent exfiltration incidents.
* If a user initiates an export with `Data Only` or `Structure and Data` on a table with more than 5,000,000 estimated rows, a non-blocking performance notification is displayed:
  > **Note:** Table `<name>` contains approximately 5.2M rows. Using PostgreSQL Custom Dump (`.dump`) is recommended for optimal speed.

---

## 9. Implementation Milestones & Roadmap

```
+----------------------------------------------------------------------------------------------------+
|                                    DEVELOPMENT MILESTONES                                          |
+-------------+------------------------------------+------------+------------------------------------+
| Milestone   | Scope & Deliverables               | Duration   | Dependencies                       |
+-------------+------------------------------------+------------+------------------------------------+
| Phase 1     | PostgreSQL Schema Introspection &  | 3 Days     | PostgresService, SchemaViewModel   |
|             | System Catalog Exclusion Engine    |            |                                    |
| Phase 2     | Toolchain pg_dump Command Builder  | 2 Days     | PostgresToolchainService           |
|             | (Custom Binary & SQL formats)      |            |                                    |
| Phase 3     | Native Swift Streaming Engine      | 3 Days     | PostgresNIO, BufferedFileHandle    |
|             | (Topological DDL & Sequence Sync)  |            |                                    |
| Phase 4     | ExportSheet UI Overhaul            | 2 Days     | SwiftUI ExportSheet, ViewModels    |
|             | (Schema/Table Tree & Multi-Scope)  |            |                                    |
| Phase 5     | SSH Tunnel Routing, Cancellation,  | 2 Days     | NIOSSH, QA Test Suite              |
|             | Large File (>10GB) Benchmarking    |            |                                    |
+-------------+------------------------------------+------------+------------------------------------+
| Total       | Complete Delivery                  | 12 Days    | Target: Postgrace v2.2             |
+-------------+------------------------------------+------------+------------------------------------+
```

---

## 10. QA Verification & Test Matrix

| Test ID | Category | Scenario | Expected Behavior | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TC-01** | Scope | Export full database via `pg_dump` | Excludes `pg_catalog` and `information_schema`; dumps all user schemas. | Planned |
| **TC-02** | Scope | Export single schema `audit` | DDL contains `CREATE SCHEMA IF NOT EXISTS "audit"` and `SET search_path = "audit"`. | Planned |
| **TC-03** | Toolchain | Export on system without `pg_dump` | Gracefully falls back to Native Swift engine; generates clean `.sql` script. | Planned |
| **TC-04** | Types | Schema containing custom ENUM | `CREATE TYPE` is emitted prior to `CREATE TABLE` that uses it. | Planned |
| **TC-05** | Sequences | Table with identity / sequence | Generates sequence DDL and `SELECT setval(...)` with correct max ID. | Planned |
| **TC-06** | FK Ordering | Two schemas with inter-schema FKs | Tables created first; foreign keys added via `ALTER TABLE` in Stage 10. | Planned |
| **TC-07** | Performance | 1,000,000 row table export | Memory footprint stays $< 75\text{ MB}$; no app freeze on Apple Silicon. | Planned |
| **TC-08** | Cancellation | User clicks Cancel at 50% progress | Subprocess or Swift Task terminated; incomplete temporary file deleted. | Planned |
| **TC-09** | SSH Tunnel | Remote server behind bastion | `pg_dump` correctly binds to `127.0.0.1:<tunnel_port>` and succeeds. | Planned |
| **TC-10** | Modes | "Structure Only" selection | Outputs schema DDL, views, and indexes; zero `INSERT` or `COPY` statements. | Planned |

---

## 11. Appendix: PostgreSQL Export Command Reference

### Full Database Binary Dump
```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d production_db \
  --clean --if-exists \
  -F c -f ~/Downloads/production_db.dump
```

### Single Schema Plain SQL Dump (Structure Only)
```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d production_db \
  -n "billing" \
  --schema-only \
  -F p -f ~/Downloads/billing_structure.sql
```

### Multi-Schema Plain SQL Dump (Structure & Data)
```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d production_db \
  -n "public" -n "audit" \
  --clean --if-exists \
  -F p -f ~/Downloads/public_and_audit.sql
```
