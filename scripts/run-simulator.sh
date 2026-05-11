#!/bin/bash
# Build for iOS Simulator and install/launch
set -e

cd "$(dirname "$0")/.."

DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
BUNDLE_ID="com.cqupt.rollcall.CQUPTRollcall"

# Generate Xcode project
command -v xcodegen >/dev/null || { echo "Run: brew install xcodegen"; exit 1; }
xcodegen generate

# Boot simulator if needed
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator

# Build for simulator
echo "Building for simulator..."
xcodebuild -project CQUPTRollcall.xcodeproj \
    -scheme CQUPTRollcall \
    -sdk iphonesimulator \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    build | tail -20

APP=$(find build -name "*.app" -path "*Debug-iphonesimulator*" -type d | head -1)
echo "App: $APP"

# Install + launch
xcrun simctl install booted "$APP"
xcrun simctl launch booted "$BUNDLE_ID"
echo "Launched. Bundle ID: $BUNDLE_ID"
