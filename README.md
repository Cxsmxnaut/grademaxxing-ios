# Grademaxxing for iOS

Native SwiftUI companion to [Grademaxxing](https://github.com/Cxsmxnaut/grademaxxing). Requires iOS 17 or later and Swift 6. The app uses Grademaxxing's existing read-only HTTPS backend.

**Status: implementation available; iPhone and live-account validation pending.** This is not a TestFlight or App Store release. Local macOS debug/release builds, 73 synthetic native checks, and Mac Catalyst type checking passed. iPhone builds, UI tests, Keychain/file-protection runtime checks, signing, and distribution disclosures remain on the [plan](ios/PLAN.md). See the [validation evidence](ios/VALIDATION.md) for the exact limits of those checks.

## Open and run

Open `ios/Grademaxxing.xcodeproj` in full Xcode, select the shared **Grademaxxing** scheme, and choose an installed iPhone simulator. The scheme starts with `--demo`: invented records, no school requests.

```sh
cd ios
swift run GrademaxxingChecks
python3 scripts/generate-project.py --check
```

The [native setup guide](ios/README.md) includes simulator commands and configuration. The default API origin is pre-production. The GitHub Actions workflow builds/tests the synthetic iPhone demo on an Xcode runner; a passing run verifies that runner, not a physical device or a real StudentVUE account.

## Implemented

- Native sign-in, session restoration, password-only reconnect, and sign-out.
- Gradebook, reporting periods, course assignments, category totals, and search.
- Local assignment editing, exclusion, extra credit, what-if/target calculations, estimated trends, and GPA planning.
- Attendance, school calendar, schedule, and student profile.
- Documents, read-only mail, and validated PDF/image previews.

Official marks remain separate from estimates. Passwords are never saved; opaque sessions use device-only Keychain. School records stay in memory, and protected temporary preview files are removed on dismissal, sign-out, and relaunch. Never use a real account for automated tests or commit credentials, student records, or screenshots.

## Fixture maintenance

The Swift app and native checks have no Node dependencies. The TypeScript fixture generators import the original web modules; run `python3 ios/scripts/regenerate-fixtures.py --web-root /path/to/grademaxxing` with an installed web checkout to regenerate them. This preserves the shared calculation/contract reference without copying the website into this repository.

## License and attribution

AGPLv3; see [LICENSE.txt](LICENSE.txt) and [NOTICE.md](NOTICE.md). Grademaxxing is derived from GradeCompass and is independent of Edupoint and school districts. StudentVUE is a trademark of Edupoint. No backend deployment is included here.
