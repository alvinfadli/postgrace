# Postgrace Quality Assurance (QA) Standards

When developing, refactoring, or reviewing code in the Postgrace repository, all agents must adhere to the following QA guidelines:

1. **Compilation & Warning Hygiene**:
   - The project must compile cleanly with 0 errors and 0 warnings under Swift 5.9+ / macOS 14+.
   - Never leave unresolved syntax errors, deprecated API usage without reason, or broken closures.

2. **Test Coverage Requirements**:
   - Every new feature, view model change, or database driver modification must be accompanied by unit tests in `Tests/PostgraceTests/`.
   - Never break existing tests in `SQLSafetyAnalyzerTests`, `ViewModelTests`, `ModelTests`, or `DataTransferTests`.

3. **Data Safety First**:
   - Changes to query execution paths must respect `SQLSafetyAnalyzer` and safe mode flags.
   - Any query altering schema or modifying data must undergo proper risk classification (`SAFE`, `ELEVATED`, `CRITICAL`).

4. **macOS Native UX & Focus Protocol**:
   - Ensure AppKit activation policies and window key status are maintained.
   - Any new text input view must support `@FocusState` and proper keyboard focus management.

5. **Credentials & Keychain Security**:
   - Database credentials must never be exposed in plaintext, printed in logs, or serialized into unencrypted configurations.
