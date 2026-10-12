#!/bin/bash
# Compile the shared core and type-check the UIKit/iOS source branches through the
# Mac Catalyst frameworks in an Apple macOS SDK. This is not an iPhone build.
set -euo pipefail
cd "$(dirname "$0")/.."
native_sdk=$(xcrun --show-sdk-path)
native_frameworks="$native_sdk/System/iOSSupport/System/Library/Frameworks"
if [ ! -d "$native_frameworks/UIKit.framework" ]; then
  echo "This SDK does not include Mac Catalyst UIKit frameworks." >&2
  exit 1
fi
mkdir -p .build/catalyst-check
xcrun swiftc -swift-version 6 -sdk "$native_sdk" -target arm64-apple-ios17.0-macabi \
  -F "$native_frameworks" -I "$native_sdk/System/iOSSupport/usr/include" \
  -emit-module -parse-as-library -module-name GrademaxxingCore \
  Sources/GrademaxxingCore/*.swift \
  -emit-module-path .build/catalyst-check/GrademaxxingCore.swiftmodule
xcrun swiftc -swift-version 6 -sdk "$native_sdk" -target arm64-apple-ios17.0-macabi \
  -F "$native_frameworks" -I "$native_sdk/System/iOSSupport/usr/include" \
  -I .build/catalyst-check -typecheck -parse-as-library App/*.swift
echo "Shared core and UIKit/iOS source branches pass Mac Catalyst type checking."
