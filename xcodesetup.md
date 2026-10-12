# Xcode handoff

Clone this repository on the Mac with full Xcode (Swift 6) and an installed iPhone simulator runtime:

```sh
git clone https://github.com/Cxsmxnaut/grademaxxing-ios.git
cd grademaxxing-ios
open ios/Grademaxxing.xcodeproj
```

Read `AGENTS.md` and `ios/VALIDATION.md`. Select the **Grademaxxing** scheme and an iPhone simulator. Keep **Run → Arguments → `--demo`** enabled; the demo and UI tests use invented data. Run with **⌘R**, then run the seven UI tests with **⌘U**.

For terminal checks, adjust the Xcode path if needed and replace the destination placeholder with an available iPhone UDID:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
cd ios
swift run GrademaxxingChecks
xcodebuild test -project Grademaxxing.xcodeproj -scheme Grademaxxing \
  -destination 'platform=iOS Simulator,id=<available-iPhone-UDID>' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

The next agent should fix build/test failures, check a small and large iPhone with Dynamic Type, verify navigation and preview/background behavior, and update `ios/VALIDATION.md` with actual results. Check the **Native iOS checks** GitHub Actions run for existing failures first. Regenerate the project after adding/removing app files: `python3 scripts/generate-project.py` from `ios/`.

No signing team is needed for simulator work. Physical-device signing, live-account testing, and distribution remain separate steps; live school testing requires explicit authorization and a designated test account. Do not commit credentials, student data, screenshots, or generated build files.
