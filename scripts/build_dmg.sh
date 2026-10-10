#!/bin/bash
set -euo pipefail

# ==============================================================================
# Postgrace: Build, Sign, and Package macOS DMG (Option A: Native hdiutil)
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Postgrace"
BUNDLE_ID="com.postgrace.app"
VERSION="${VERSION:-1.0.0}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_ROOT="${DIST_DIR}/dmg_root"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
ENTITLEMENTS_FILE="${PROJECT_ROOT}/scripts/Postgrace.entitlements"
INFO_PLIST_TEMPLATE="${PROJECT_ROOT}/scripts/Info.plist"

echo "=========================================================="
echo " Building ${APP_NAME} v${VERSION} (${BUILD_CONFIG})"
echo "=========================================================="

# 1. Detect Code Signing Identity
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    # Check if a Developer ID Application certificate exists in Keychain
    DEV_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}' || true)
    if [ -n "${DEV_ID}" ]; then
        SIGNING_IDENTITY="${DEV_ID}"
        echo "--> Found Developer ID certificate: ${SIGNING_IDENTITY}"
    else
        SIGNING_IDENTITY="-"
        echo "--> No Developer ID certificate found. Using ad-hoc signing (-)."
    fi
else
    echo "--> Using specified signing identity: ${SIGNING_IDENTITY}"
fi

# 2. Build Release Binary using Swift Package Manager
echo "--> Compiling release executable with SwiftPM..."
cd "${PROJECT_ROOT}"
swift build -c "${BUILD_CONFIG}"

# Locate compiled binary
BIN_PATH=""
if [ -f "${PROJECT_ROOT}/.build/${BUILD_CONFIG}/${APP_NAME}" ]; then
    BIN_PATH="${PROJECT_ROOT}/.build/${BUILD_CONFIG}/${APP_NAME}"
elif [ -f "${PROJECT_ROOT}/.build/arm64-apple-macosx/${BUILD_CONFIG}/${APP_NAME}" ]; then
    BIN_PATH="${PROJECT_ROOT}/.build/arm64-apple-macosx/${BUILD_CONFIG}/${APP_NAME}"
elif [ -f "${PROJECT_ROOT}/.build/x86_64-apple-macosx/${BUILD_CONFIG}/${APP_NAME}" ]; then
    BIN_PATH="${PROJECT_ROOT}/.build/x86_64-apple-macosx/${BUILD_CONFIG}/${APP_NAME}"
fi

if [ -z "${BIN_PATH}" ] || [ ! -f "${BIN_PATH}" ]; then
    echo "Error: Compiled binary not found in .build/" >&2
    exit 1
fi
echo "--> Found binary: ${BIN_PATH}"

# 3. Assemble .app Bundle
echo "--> Assembling ${APP_NAME}.app bundle..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy App Icon
if [ -f "${PROJECT_ROOT}/Sources/Postgrace/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_ROOT}/Sources/Postgrace/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Copy SPM Resource Bundles from release build directory
BIN_DIR="$(dirname "${BIN_PATH}")"
if [ -d "${BIN_DIR}" ]; then
    find "${BIN_DIR}" -maxdepth 1 -name "*.bundle" -type d | while read -r bundle; do
        if [ -d "${bundle}" ]; then
            echo "    Including resource bundle: $(basename "$bundle")"
            cp -Rf "$bundle" "${APP_BUNDLE}/Contents/Resources/"
        fi
    done
fi

# Copy & stamp Info.plist
cp "${INFO_PLIST_TEMPLATE}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true

# Write PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 4. Code Sign the Application Bundle
echo "--> Signing ${APP_NAME}.app with identity: '${SIGNING_IDENTITY}'..."
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    codesign --force --deep --sign - \
        --entitlements "${ENTITLEMENTS_FILE}" \
        "${APP_BUNDLE}"
else
    # Full hardened runtime for Developer ID distribution
    codesign --force --deep --options runtime \
        --sign "${SIGNING_IDENTITY}" \
        --entitlements "${ENTITLEMENTS_FILE}" \
        "${APP_BUNDLE}"
fi

# Verify signature
echo "--> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
echo "    Code signature verified successfully."

# 5. Build DMG Image using native hdiutil
echo "--> Creating disk image (DMG) via native hdiutil..."
mkdir -p "${DMG_ROOT}"
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"

# Add Applications symlink for drag-and-drop installation
ln -s /Applications "${DMG_ROOT}/Applications"

# Generate compressed, read-only DMG (UDZO)
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# Clean up staging root
rm -rf "${DMG_ROOT}"

# 6. Sign DMG if non-adhoc identity
if [ "${SIGNING_IDENTITY}" != "-" ]; then
    echo "--> Signing ${APP_NAME}.dmg..."
    codesign --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
fi

# 7. Summary
FILE_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')
SHA256_HASH=$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')

echo ""
echo "=========================================================="
echo " Build & Packaging Successful!"
echo "=========================================================="
echo " App Bundle:  ${APP_BUNDLE}"
echo " DMG Image:   ${DMG_PATH}"
echo " DMG Size:    ${FILE_SIZE}"
echo " SHA-256:     ${SHA256_HASH}"
echo " Signing:     ${SIGNING_IDENTITY}"
echo "=========================================================="

if [ "${SIGNING_IDENTITY}" != "-" ]; then
    echo ""
    echo "To notarize for public distribution, run:"
    echo "  xcrun notarytool submit \"${DMG_PATH}\" --keychain-profile \"<PROFILE_NAME>\" --wait"
    echo "  xcrun stapler staple \"${DMG_PATH}\""
fi
