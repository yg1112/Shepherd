#!/bin/bash

# =============================================================================
# Build script for Shepherd.app
# Supports: Development build, Signed build, and Notarized distribution
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="Shepherd"
BUNDLE_ID="com.shepherd.app"
APP_PATH="/Applications/${APP_NAME}.app"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME_NAME="Shepherd"

# Developer ID - Shared across all apps under same developer account
# These are account-level credentials, not app-specific
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: DZG Studio LLC (DRV5ZMT5U8)}"
TEAM_ID="${TEAM_ID:-DRV5ZMT5U8}"

# Notarization - Uses keychain profile (shared across apps)
# The "ResoNotary" profile stores Apple ID credentials and can notarize any app
NOTARY_PROFILE="${NOTARY_PROFILE:-ResoNotary}"

# Build configuration
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"

# Parse arguments
BUILD_MODE="dev"  # dev, signed, release
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dev) BUILD_MODE="dev" ;;
        --signed) BUILD_MODE="signed" ;;
        --release) BUILD_MODE="release" ;;
        --clean) CLEAN_BUILD=true ;;
        --help|-h)
            echo "Usage: $0 [--dev|--signed|--release] [--clean]"
            echo ""
            echo "Options:"
            echo "  --dev      Development build (no signing, default)"
            echo "  --signed   Signed build with Developer ID"
            echo "  --release  Full release build with signing + notarization"
            echo "  --clean    Clean build folder before building"
            echo ""
            echo "Environment variables (optional overrides):"
            echo "  DEVELOPER_ID   - Developer ID certificate (default: DZG Studio LLC)"
            echo "  TEAM_ID        - Apple Developer Team ID (default: DRV5ZMT5U8)"
            echo "  NOTARY_PROFILE - Keychain profile for notarization (default: ResoNotary)"
            echo ""
            echo "To create a dedicated notarization profile for Shepherd:"
            echo "  xcrun notarytool store-credentials \"ShepherdNotary\" --apple-id \"your@email.com\" --team-id \"DRV5ZMT5U8\""
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Building ${APP_NAME} (${BUILD_MODE} mode)${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Clean if requested
if [[ "${CLEAN_BUILD}" == true ]]; then
    echo -e "\n${YELLOW}[1/6] Cleaning build folder...${NC}"
    rm -rf "${BUILD_DIR}"
    xcodebuild clean -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" -scheme "${SCHEME_NAME}" -configuration Release 2>/dev/null || true
    echo -e "${GREEN}Clean complete${NC}"
else
    echo -e "\n${YELLOW}[1/6] Skipping clean (use --clean to force)...${NC}"
fi

# Create build directory
mkdir -p "${BUILD_DIR}"

# Step 2: Build using xcodebuild
echo -e "\n${YELLOW}[2/6] Building with xcodebuild...${NC}"

if [[ "${BUILD_MODE}" == "dev" ]]; then
    # Development build - no signing
    xcodebuild build \
        -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        | grep -E "^(Build|Compiling|Linking|error:|warning:)" || true
else
    # Signed build - use Developer ID
    xcodebuild build \
        -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        CODE_SIGN_STYLE="Manual" \
        | grep -E "^(Build|Compiling|Linking|error:|warning:)" || true
fi

# Check if build succeeded
BUILT_APP="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo -e "${RED}Build failed! App not found at ${BUILT_APP}${NC}"
    exit 1
fi
echo -e "${GREEN}Build successful${NC}"

# Step 3: Kill existing app
echo -e "\n${YELLOW}[3/6] Stopping existing app...${NC}"
killall "${APP_NAME}" 2>/dev/null || true
sleep 1

# Step 4: Remove old app and install new one
echo -e "\n${YELLOW}[4/6] Installing app to /Applications...${NC}"
rm -rf "${APP_PATH}"
cp -R "${BUILT_APP}" "${APP_PATH}"

# Clear extended attributes
xattr -cr "${APP_PATH}"

echo -e "${GREEN}App installed${NC}"

# Step 5: Code signing (for signed and release builds)
if [[ "${BUILD_MODE}" == "signed" || "${BUILD_MODE}" == "release" ]]; then
    echo -e "\n${YELLOW}[5/6] Code signing with Hardened Runtime...${NC}"

    # Create a release entitlements file (without get-task-allow)
    RELEASE_ENTITLEMENTS="/tmp/${APP_NAME}-release.entitlements"
    cat > "${RELEASE_ENTITLEMENTS}" << 'ENTITLEMENTS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS_EOF

    # Re-sign with hardened runtime, timestamp, and proper entitlements
    codesign --force --deep --timestamp --options runtime \
        --entitlements "${RELEASE_ENTITLEMENTS}" \
        --sign "${DEVELOPER_ID}" \
        "${APP_PATH}"

    # Verify signature
    codesign --verify --verbose "${APP_PATH}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Code signing successful${NC}"
    else
        echo -e "${RED}Code signature verification failed${NC}"
        exit 1
    fi

    # Clean up
    rm -f "${RELEASE_ENTITLEMENTS}"
else
    echo -e "\n${YELLOW}[5/6] Skipping code signing (dev build)...${NC}"
fi

# Step 6: Notarization (for release builds only)
if [[ "${BUILD_MODE}" == "release" ]]; then
    echo -e "\n${YELLOW}[6/6] Notarizing app...${NC}"

    # Create a zip for notarization
    NOTARIZE_ZIP="/tmp/${APP_NAME}-notarize.zip"
    rm -f "${NOTARIZE_ZIP}"
    ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

    # Submit for notarization using keychain profile
    echo "Submitting to Apple for notarization (using keychain profile: ${NOTARY_PROFILE})..."
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait 2>&1)

    echo "${NOTARIZE_OUTPUT}"

    # Check if notarization was accepted (look for "status: Accepted")
    if echo "${NOTARIZE_OUTPUT}" | grep -q "status: Accepted"; then
        echo -e "${GREEN}Notarization successful${NC}"

        # Staple the notarization ticket to the app
        echo "Stapling notarization ticket..."
        xcrun stapler staple "${APP_PATH}"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Stapling successful${NC}"
        else
            echo -e "${YELLOW}Warning: Stapling failed (app is still notarized)${NC}"
        fi
    else
        echo -e "${RED}Notarization failed${NC}"
        # Extract submission ID and show log
        SUBMISSION_ID=$(echo "${NOTARIZE_OUTPUT}" | grep "id:" | head -1 | awk '{print $2}')
        if [ -n "${SUBMISSION_ID}" ]; then
            echo "Fetching notarization log..."
            xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${NOTARY_PROFILE}"
        fi
        echo ""
        echo "If the keychain profile doesn't exist, create it with:"
        echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id \"your@email.com\" --team-id \"${TEAM_ID}\""
        exit 1
    fi

    # Clean up
    rm -f "${NOTARIZE_ZIP}"
else
    echo -e "\n${YELLOW}[6/6] Skipping notarization (not a release build)...${NC}"
fi

# Done!
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  ${APP_NAME}.app installed to /Applications${NC}"
echo -e "${GREEN}========================================${NC}"

# Launch the app (dev builds only)
if [[ "${BUILD_MODE}" == "dev" ]]; then
    echo -e "\nLaunching app..."
    open "${APP_PATH}"
fi

echo ""
echo "Build mode: ${BUILD_MODE}"
if [[ "${BUILD_MODE}" == "release" ]]; then
    echo -e "${GREEN}App is signed and notarized - ready for distribution!${NC}"
    echo "Next: Create a DMG for distribution if needed"
elif [[ "${BUILD_MODE}" == "signed" ]]; then
    echo -e "${YELLOW}App is signed but not notarized${NC}"
    echo "Run with --release for full distribution build"
fi
