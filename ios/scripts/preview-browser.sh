#!/bin/bash
# Build and stream the real iPhone app; run on the Mac with full Xcode.
set -euo pipefail
native_root="${GRADEMAXXING_IOS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bash ios/scripts/preview-browser.sh [iPhone-simulator-UDID]"
  echo "Requires full Xcode, an installed iPhone runtime, Node.js 20+, and Python 3."
  echo "Starts the synthetic demo and serve-sim on http://127.0.0.1:3200."
  exit 0
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1 || ! xcrun --find simctl >/dev/null 2>&1; then
  echo "Full Xcode and its iOS simulator tools are missing on this Mac." >&2
  echo "Run this script on your Xcode laptop, or set DEVELOPER_DIR to its Xcode installation." >&2
  exit 1
fi
command -v python3 >/dev/null
command -v npx >/dev/null

native_selection="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = [device for runtime, entries in json.load(sys.stdin)["devices"].items()
           if ".iOS-" in runtime for device in entries
           if device.get("isAvailable") and (".iPhone-" in device.get("deviceTypeIdentifier", "")
                                             or device["name"].startswith("iPhone"))]
requested = sys.argv[1]
if requested:
    devices = [device for device in devices if device["udid"] == requested]
if not devices:
    raise SystemExit("No matching iPhone simulator. Install an iOS runtime in Xcode first.")
device = next((device for device in devices if device["state"] == "Booted"), devices[0])
print(device["udid"], device["state"])
' "${1:-}")"
read -r native_device native_state <<< "$native_selection"
if [[ "$native_state" != "Booted" ]]; then
  xcrun simctl boot "$native_device"
fi
xcrun simctl bootstatus "$native_device" -b

native_derived="$native_root/.build/browser-preview"
xcodebuild build -quiet \
  -project "$native_root/Grademaxxing.xcodeproj" -scheme Grademaxxing \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$native_device" \
  -derivedDataPath "$native_derived" CODE_SIGNING_ALLOWED=NO
native_app="$native_derived/Build/Products/Debug-iphonesimulator/Grademaxxing.app"
native_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$native_app/Info.plist")"
xcrun simctl install "$native_device" "$native_app"
xcrun simctl launch --terminate-running-process "$native_device" "$native_bundle_id" --demo

echo "Opening the real simulator stream at http://127.0.0.1:3200 (synthetic demo only)."
echo "Open that address in Codex Browser on this Mac, or use a private SSH port forward."
exec npx --yes serve-sim@0.1.48 "$native_device" \
  --host 127.0.0.1 --port 3200 --fit --panes devices,tools
