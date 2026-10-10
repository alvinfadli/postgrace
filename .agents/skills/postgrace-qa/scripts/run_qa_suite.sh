#!/bin/bash
set -eo pipefail

echo "=================================================="
echo " Postgrace Comprehensive QA Verification Suite"
echo "=================================================="

# Check Swift environment
echo "[1/4] Checking Swift Toolchain..."
swift --version

# Step 1: Clean build check
echo "[2/4] Verifying clean compilation..."
swift build -c debug

# Step 2: Automated Test Execution
echo "[3/4] Running automated test suite..."
swift test --parallel

# Step 3: Summary
echo "[4/4] QA suite run finished successfully!"
echo "All test targets passed with 0 errors."
