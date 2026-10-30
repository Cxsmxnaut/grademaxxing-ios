# App Store submission preparation

Prepared October 30, 2026. **Not ready to submit yet.** Source preparation is implemented; current iPhone QA, privacy-policy publication, Apple team configuration, and a signed distribution build remain open. Nothing has been uploaded or submitted. All work in this pass was headless.

## Prepared in the native repository

- Release uses `https://grademaxxing.app`; Debug uses `https://dev.grademaxxing.app`. The plist reads build settings, so version/build overrides are reflected in the binary and Account screen. Initial candidate: **1.0.0 (1)**, iPhone, iOS 17+, existing bundle ID `app.grademaxxing.native` pending confirmation on the owning team.
- A 1024 × 1024 opaque RGB icon uses the existing native brand mark. Source artwork is 338 × 338; inspect the generated icon on a real device before accepting the enlarged artwork as final.
- Data and privacy is available before sign-in and from Account. AGPL/project notices and font licenses are available offline from Account. The source link must point to the exact source offered with the distributed build.
- The privacy manifest declares account-linked user ID, product interaction, and conservatively district-inferred state as coarse location, with no tracking. These cover the inspected backend's pseudonymous usage counters; this is a candidate disclosure to reconcile with the deployed service and App Store Connect.
- `scripts/release-preflight.py` checks the generated project, configuration, icon, bundled notices, and privacy manifest. With `--archive`, it additionally inspects the built device app, SDK, embedded resources, arm64 executable, debug symbols, and signature unless explicitly allowed unsigned.
- CI targets a submission-capable macOS/Xcode runner and tests the exact synthetic UI class on small/large iPhones at normal text size and a large iPhone at the largest text size. An independent unsigned Release device archive job checks build/assets while UI tests run; the workflow remains failed unless every job passes. Readable JSON results and synthetic screenshot attachments are exported for headless review.
- [English store metadata](AppStore/en-US.json) is drafted and character-count checked. Review notes request permission to use the synthetic demo; Apple has not approved that request.

## Remaining gates, in order

| Gate | Evidence or next action | Owner |
| --- | --- | --- |
| Xcode execution | Headless CI now builds the device archive and runs the full synthetic class. The first small-iPhone run passed 13 functional cases, including the manual district picker; the accessibility case failed. The readability/touch-target/large-text fixes need a fresh passing matrix. This Mac has Command Line Tools only, and the documented remote host timed out. | Engineering |
| Device quality | Re-run a small/large iPhone matrix, largest text, VoiceOver, Reduce Motion/Transparency, keyboard dismissal, background/privacy cover, offline/resume, reconnect, previews, session expiry, and sign-out/account isolation. Preserve existing audit failures and exclusions; do not turn unexplained failures into exclusions. Earlier device evidence does not validate this revision. | Engineering / QA |
| Apple ownership | Supply the paid developer Team ID, verify bundle ID availability, create the App Store Connect app record, and confirm distribution signing/provisioning. Keep signing account material outside Git. No Team ID was supplied in this pass. | App owner |
| Public privacy and support | The public privacy URL returned HTTP 200 but describes browser storage and website/Max features. Publish native-specific handling, a real privacy/support contact, effective date, service processors, usage retention/deletion, and a working support URL. The current public notice does not explain the inspected native-accessible usage counters. In-app explanations alone do not finish this gate. | Product / privacy owner |
| Backend privacy reconciliation | Verify the deployed revision and analytics configuration. The local web checkout is on `pre-prod`; it is evidence of implementation, not proof of production settings. The retained HMAC account identifier, first/last activity, active dates, and district state are linked usage data. No expiry/deletion for those rows was found in the inspected usage code/migrations. Define retention and a request/deletion path; sign-out clears native records/session but does not remove those usage rows. Verify hosting log retention/access and any other server record retention. | Backend / privacy owner |
| Audience and permissions | Confirm intended ages, territories, and student-directed release model; resolve under-13 handling, school/vendor integration permissions, and privacy review. Any school-directed deployment needs district/counsel review and the appropriate agreement. Complete Apple's age-rating and accessibility-label questionnaires from evidence. | App owner / privacy / district where applicable |
| License/source distribution | Preserve AGPL and attribution. Verify public access to the exact corresponding source and review compatibility of the intended App Store distribution terms with the existing license. Bundling license text alone does not settle distribution rights. | App owner / license reviewer |
| Review access and screenshots | Obtain Apple's approval for built-in demo review access, or arrange an authorized synthetic school/vendor review account outside Git. Never submit a real student's credentials. Capture fresh synthetic screenshots from this revision at Apple's required iPhone sizes; historical preview captures are not this build. | App owner / QA |
| Distribution artifact | An unsigned Release device archive at `18061ae` passed hosted and local artifact inspection: 1.0.0 (1), production API, arm64, iPhone/iOS 17+, iOS 26.5 SDK, compiled icon, privacy resource, and dSYM. After the other gates, create a signed archive, export for App Store Connect, validate with Apple, enter the reviewed metadata/privacy/support answers, choose the build, and submit. | App owner / release engineering |

## Headless commands

From `ios/`:

```sh
swift run GrademaxxingChecks
python3 scripts/release-preflight.py
xcrun swift-format lint --strict --recursive App Sources Tests UITests Package.swift scripts/build-app-icon.swift
```

On a Mac with full Xcode 26 or later and an iOS 26 or later SDK, use an installed Xcode path through command-scoped `DEVELOPER_DIR`. This does not change the machine-wide selection. Never run `open`, start a browser preview, or reveal Organizer for this task.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/archive.sh --unsigned
```

The unsigned engineering archive goes to `.build/release/Grademaxxing.xcarchive`. The script refuses to overwrite an existing archive. For an owning team already configured with Xcode, set `GRADEMAXXING_DEVELOPMENT_TEAM` locally and use `--signed`. It permits automatic provisioning and verifies the archive signature; it does not export, upload, or submit. An archive can be development-signed before distribution export, so this check does not certify an App Store distribution profile. Existing automatic-signing settings are retained, and no team override is persisted in the generated project.

For headless UI tests, boot an existing dedicated synthetic simulator with `simctl boot`/`bootstatus`, then run the shared scheme with `-parallel-testing-enabled NO -only-testing:GrademaxxingUITests/GrademaxxingUITests`. Keep `--demo` in every automated launch; never include untracked live-account test classes. CI records xcresult evidence even on failure.

## Data map used for the privacy review

| Path | Data / recipient | Retention and clearing |
| --- | --- | --- |
| Sign-in / reconnect | District URL, username, password → Grademaxxing HTTPS service → selected StudentVUE portal | Native input clears on submit. Password is not saved by native code. Backend source discards password after authentication; verify deployed logging/processor configuration. |
| Session | District, username, session ID and encrypted session cookie in device-only, when-unlocked Keychain; authenticated requests to Grademaxxing | Device Keychain scoped by service host. Sign-out deletes local session even if remote request fails; expiry clears invalid saved sessions. Backend cookie lifetime defaults to 12 hours and can be configured. Inspected server logout does not revoke a copied stateless token; do not claim immediate server-side revocation. |
| School reads | Grades, assignments, attendance, events, schedule, profile, documents and mail via Grademaxxing → native memory | Cleared on sign-out/account invalidation; resource caches stay in memory. Confirm service/host retention independently. No native persistent record cache or AI requests. |
| Preview | Requested PDF/image bytes → protected private temporary file → Quick Look | One file at a time; dismissal, sign-out/reconnect and next launch clean up. Cleanup errors are surfaced. Physical-device file-protection behavior remains a QA gate. |
| Service usage | HMAC district/username identifier, first/last activity, daily activity and district state → Cloudflare D1; aggregate increments → Analytics Engine | Inspected session POST/status/keepalive call usage recording. No usage-row retention/deletion policy verified. District state is inferred from the school catalog, not GPS. |
| Demo / local plans | Invented records and local calculations | No school requests; no grade/plan upload. Automated test evidence must remain synthetic. |
| External links | User-initiated privacy/source/portal HTTPS navigation | External site policies apply. No embedded web tracking SDK added to the app. |

Evidence: native `AppModel.swift`, `APIClient.swift`, `KeychainSessionVault.swift`, `PreviewFiles.swift`; sibling web checkout `src/routes/api/session/{+server.ts,status/+server.ts,keepalive/+server.ts}`, `src/lib/server/student-session.ts`, `src/lib/server/analytics/usage.ts`, `migrations/0001_unique_student_usage.sql`, `0002_daily_student_activity.sql`, `0009_student_state.sql`, and `wrangler.jsonc`. This is an engineering review, not a claim of legal compliance or school approval.

## Apple references checked October 30, 2026

- [Submission SDK requirements](https://developer.apple.com/news/upcoming-requirements/): Xcode 26+ and iOS 26+ SDK; iOS 17 minimum deployment remains supported.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), §2.1: complete final app and review access; a built-in demo in lieu of credentials needs prior Apple approval.
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/): disclose retained backend data, including linked pseudonymous identifiers. Request-only transient processing and on-device-only data are treated differently; verify actual retention before final answers.
- [Encryption export guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations): the native client uses system HTTPS/Keychain, with no custom cryptography; `ITSAppUsesNonExemptEncryption` is false. Reassess if cryptographic functionality changes.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/): use current required iPhone sizes and only invented records.

The unresolved gates above are separate from the automated source preflight. That command intentionally reports its limited scope and links here; it must never be presented as proof of submission readiness.
