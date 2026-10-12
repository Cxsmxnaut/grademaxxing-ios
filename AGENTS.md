# Native repository instructions

Read `README.md`, `ios/PLAN.md`, and `ios/VALIDATION.md` before changing the app.

- Keep the existing AGPL license and attribution.
- Keep StudentVUE access read-only. Separate official values from local estimates.
- Never store, log, print, fixture, or commit real credentials, cookies, student records, or student screenshots. All automated checks use synthetic demo data.
- Preserve request serialization, Keychain isolation, response bounds, preview cleanup, and stale-result invalidation.
- Live account tests need explicit user authorization and a designated test account provided outside source control.
- Never claim iPhone or device validation from a macOS/Catalyst compile alone. Record actual validation evidence.
- After changing native code, run `swift run GrademaxxingChecks` from `ios/`, check formatting and project generation, and run the shared Xcode scheme when Xcode is available. Regenerate the project after adding/removing app sources.
- This repository contains the iOS client only. Pushing it does not authorize a web/backend deployment or an App Store/TestFlight release.
- Honor the user's machine account preference: default to `lolakapuri1`; use `Cxsmxnaut` only for explicitly authorized operations, with temporary overrides and cleanup.
