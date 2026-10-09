#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
collect_evidence() {
  mkdir -p build/screenshots/compact
  if [[ -d build/GestureSmokeResults.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/GestureSmokeResults.xcresult --output-path build/screenshots/gesture-smoke || true
  fi
  if [[ -d build/TestResults.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/TestResults.xcresult --output-path build/screenshots || true
  fi
  if [[ -d build/SmallScreenResults.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/SmallScreenResults.xcresult --output-path build/screenshots/compact || true
  fi
}
trap collect_evidence EXIT
boot_simulator() {
  python3 - "$1" <<'PY'
import subprocess
import sys

device = sys.argv[1]
for attempt in range(2):
    print(f"Booting simulator {device}, attempt {attempt + 1}", flush=True)
    # Keep only one simulator alive on the memory-constrained CI runner.
    subprocess.run(["xcrun", "simctl", "shutdown", "all"], timeout=45, check=False)
    try:
        subprocess.run(["xcrun", "simctl", "boot", device], timeout=45, check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], timeout=180, check=True)
        break
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        if attempt == 1:
            raise
        print("Simulator startup failed; retrying once.", flush=True)
PY
}
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
sdk=$(xcrun --sdk iphoneos --show-sdk-version)
if [[ "${sdk%%.*}" -lt 26 ]]; then echo "Xcode with iOS 26 SDK is required." >&2; exit 1; fi
swift generate-icon.swift
xcodegen generate
swift test 2>&1 | tee build/core-tests.log
simulator=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; ids=[v["udid"] for k,vs in d.items() if "iOS-26" in k for v in vs if "iPhone" in v["name"] and v["isAvailable"]]; print(ids[0] if ids else "")')
if [[ -z "$simulator" ]]; then echo "No iOS 26 iPhone simulator is installed." >&2; exit 1; fi
boot_simulator "$simulator" 2>&1 | tee build/simulator-startup.log
xcodebuild test -project NamSolar.xcodeproj -scheme NamSolar -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -parallel-testing-enabled NO -derivedDataPath build/DerivedData \
  -only-testing:NamSolarTests/SolarChartTouchTests \
  -only-testing:NamSolarUITests/NamSolarUITests/testZoomedSOCSwipesPanWithoutChangingZoomAndInspectorStaysAbovePlot \
  -only-testing:NamSolarUITests/NamSolarUITests/testBatteryPercentAndCellChartsCanBeExpandedAndInspected \
  -only-testing:NamSolarUITests/NamSolarUITests/testEnergyDayAndInclusiveRangeChartsAndDateControls \
  -only-testing:NamSolarUITests/NamSolarUITests/testCalendarKeepsBrowsedMonthAcrossLiveTicksAndBothDateFields \
  -only-testing:NamSolarUITests/NamSolarUITests/testPullingMainPagesDoesNotShowRefreshAndManualRecoveryRemains \
  -resultBundlePath build/GestureSmokeResults.xcresult CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/gesture-smoke-tests.log
xcodebuild test -project NamSolar.xcodeproj -scheme NamSolar -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -parallel-testing-enabled NO -derivedDataPath build/DerivedData \
  -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/ios-tests.log
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; rs=json.load(sys.stdin)["runtimes"]; print(next((r["identifier"] for r in rs if r.get("isAvailable") and r["name"].startswith("iOS 26")), ""))')
small=$(xcrun simctl create NamSolar-Compact com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$runtime")
boot_simulator "$small" 2>&1 | tee -a build/simulator-startup.log
xcodebuild test -project NamSolar.xcodeproj -scheme NamSolar -configuration Debug \
  -destination "platform=iOS Simulator,id=$small" -parallel-testing-enabled NO -derivedDataPath build/DerivedData \
  -resultBundlePath build/SmallScreenResults.xcresult CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/small-screen-tests.log
xcodebuild archive -project NamSolar.xcodeproj -scheme NamSolar -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/NamSolar.xcarchive \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/archive.log
mkdir -p build/Package/Payload
cp -R build/NamSolar.xcarchive/Products/Applications/NamSolar.app build/Package/Payload/
app=build/Package/Payload/NamSolar.app
test -f "$app/NamSolar"
file "$app/NamSolar" | tee build/binary.txt
otool -l "$app/NamSolar" | grep -A 6 LC_BUILD_VERSION | tee build/deployment.txt
plutil -p "$app/Info.plist" | tee build/info.txt
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")
ipa="NamSolar-${version}-iOS26-unsigned.ipa"
(cd build/Package && zip -qr "../$ipa" Payload)
shasum -a 256 "build/$ipa" > build/SHA256.txt
echo "IPA: build/$ipa"
