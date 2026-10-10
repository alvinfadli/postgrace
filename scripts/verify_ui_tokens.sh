#!/usr/bin/env bash
set -euo pipefail

echo "=== Verifying Postgrace UI Design System Rules ==="

FAILURES=0

# Rule 1: No .buttonStyle(.borderedProminent)
echo "Checking Rule 1: No default macOS .buttonStyle(.borderedProminent)..."
if grep -rn "borderedProminent" Sources/; then
    echo "❌ ERROR: Found default macOS .buttonStyle(.borderedProminent). Use PostgraceButton instead!"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ Rule 1 passed: 0 occurrences of .borderedProminent."
fi

# Rule 2: No unstyled Color.blue in Views
echo "Checking Rule 2: No unstyled Color.blue in Sources/Postgrace/Views/..."
if grep -rn "Color\.blue" Sources/Postgrace/Views/ | grep -v "ConnectionColor\.blue"; then
    echo "❌ ERROR: Found hardcoded Color.blue. Use PostgraceTheme accent tokens instead!"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ Rule 2 passed: 0 unstyled Color.blue in Views."
fi

# Rule 3: No unstyled NSColor.systemBlue in Views
echo "Checking Rule 3: No unstyled NSColor.systemBlue in Sources/Postgrace/Views/..."
if grep -rn "systemBlue" Sources/Postgrace/Views/; then
    echo "❌ ERROR: Found NSColor.systemBlue. Use PostgraceTheme accent tokens instead!"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ Rule 3 passed: 0 unstyled NSColor.systemBlue in Views."
fi

if [ $FAILURES -gt 0 ]; then
    echo "❌ Total UI Design System Violations: $FAILURES"
    exit 1
fi

echo "✅ All UI Design System checks passed! Zero default blue components found."
