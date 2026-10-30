# Grademaxxing for iOS

Native SwiftUI companion to [Grademaxxing](https://github.com/Cxsmxnaut/grademaxxing). Requires iOS 17 or later and Swift 6. The app uses Grademaxxing's existing read-only HTTPS backend.

**Status: native implementation with initial visual validation; broader device and accessibility checks remain.** The current working copy passes 75 synthetic core checks. Demo UI results from the dedicated iPhone 17e simulator (iOS 27.0, Xcode 27.1), including district selection/search, are recorded in the validation notes. The primary-screen accessibility audit still reports one unidentified clipping issue; earlier audit results and exclusions are retained in the validation notes. Earlier CI, two-simulator, and authorized physical-device session results are preserved in the [validation evidence](ios/VALIDATION.md). VoiceOver, remaining lifecycle/device checks, final assets, signing, and distribution remain on the [plan](ios/PLAN.md). This is not a TestFlight or App Store release.

## Open and run

App Store preparation is tracked in [ios/RELEASE.md](ios/RELEASE.md). Release source configuration, app icon, in-app privacy and bundled licenses, store metadata, and headless CI/archive checks are prepared. Current iPhone QA, Apple ownership/signing, public privacy/support details, and submission remain open. No build has been uploaded.

Open `ios/Grademaxxing.xcodeproj` in full Xcode, select the shared **Grademaxxing** scheme, and choose an installed iPhone simulator. The scheme starts with `--demo`: invented records, no school requests.

```sh
cd ios
swift run GrademaxxingChecks
python3 scripts/generate-project.py --check
```

The [native setup guide](ios/README.md) includes simulator commands and configuration. Debug targets pre-production; Release targets production. The GitHub Actions workflow builds/tests the synthetic iPhone demo on an Xcode runner; a passing run verifies that runner, not a physical device or a real StudentVUE account.

## Implemented

- Native sign-in with searchable district selection, session restoration, password-only reconnect, and sign-out.
- Gradebook, reporting periods, course assignments, category totals, and search.
- Local assignment editing, exclusion, extra credit, what-if/target calculations, estimated trends, and GPA planning.
- Attendance, school calendar, schedule, and student profile.
- Documents, read-only mail, and validated PDF/image previews.

Official marks remain separate from estimates. Passwords are never saved; opaque sessions use device-only Keychain. School records stay in memory, and protected temporary preview files are removed on dismissal, sign-out, and relaunch. Never use a real account for automated tests or commit credentials, student records, or screenshots. A live account check needs explicit authorization, a designated account supplied outside source control, and a probe that keeps the credential out of the repository.

## Fixture maintenance

The Swift app and native checks have no Node dependencies. The TypeScript fixture generators import the original web modules; run `python3 ios/scripts/regenerate-fixtures.py --web-root /path/to/grademaxxing` with an installed web checkout to regenerate them. This preserves the shared calculation/contract reference without copying the website into this repository.

## License and attribution

AGPLv3; see [LICENSE.txt](LICENSE.txt) and [NOTICE.md](NOTICE.md). Grademaxxing is derived from GradeCompass and is independent of Edupoint and school districts. StudentVUE is a trademark of Edupoint. No backend deployment is included here.

## Native visual reference

The native app uses the original iOS design language: system typography, navy course cards, and native grouped lists and forms. Grademaxxing’s layout is adapted with leading letter grades, percentage bars, and a visible GPA summary. Grademaxxing’s logo and navy/green/gold identity carry the brand, with dark appearance and native Liquid Glass navigation. The current direction is recorded in [ios/DESIGN.md](ios/DESIGN.md). See [browserpreview.md](browserpreview.md) for the real simulator preview through Codex, and [ios/VALIDATION.md](ios/VALIDATION.md) for measured simulator evidence.
