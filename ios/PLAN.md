# Grademaxxing for iOS — native SwiftUI plan

Started October 11, 2026. Owner: this chat. All native work lives in `ios/` within the active Grademaxxing repository.

## Product decision

Build a real SwiftUI iPhone app, using the existing read-only Grademaxxing HTTPS backend. Do not wrap the website or move district scraping into the device. Grades are the home screen. Use native navigation, forms, refresh gestures, accessibility, and Dynamic Type, with Grademaxxing's navy, green, blue, and gold palette. Minimum deployment target: iOS 17. Use Swift 6 and no third-party app dependencies.

## 1. Foundation and first working flow

- [x] Add an Xcode project, shared scheme, configuration, asset scaffolds, and setup instructions.
- [x] Extract an independently testable Swift package for API contracts and calculations.
- [x] Implement HTTPS JSON login, session restoration, cookie rotation, keepalive, reconnect, and logout. Synthetic transport checks pass; live integration remains in phase 2.
- [x] Store only the opaque app session in device-only Keychain. Passwords are never retained. Record lists stay in memory; document and attachment previews use protected temporary copies with cleanup on dismissal/sign-out/relaunch. Keychain and file-protection runtime verification on iPhone remain in phase 2.
- [x] Serialize all session requests, including reporting-period changes; ignore outdated screen results when the user signs out or changes modes.
- [x] Decode the actual `{ xml, detailed }` gradebook response into native models without changing the backend.
- [x] Build grades, period switching, searchable course assignments, category summaries, and a clearly labeled local what-if calculator.
- [x] Add a GPA planner with editable credits/rigor and explicit provisional policy labeling.
- [x] Include a fully synthetic demo that makes no network requests, loading/empty/error states, and account controls. Native visual QA remains unverified.
- [x] Verify the Swift package and compile native views with the available macOS SDK. Run repository checks and the Cloudflare build.

Acceptance: the starter contains native screens connected to the current API, meaningful contract/session/calculation tests, and a project that is ready for an iPhone simulator build. Simulator execution remains a separate gate when Xcode is available.

## 2. iPhone validation and session hardening

- [ ] Install Xcode through the normal Apple distribution and select its developer directory; confirm an iOS simulator runtime is installed.
- [ ] Run the shared `Grademaxxing` scheme on a small and a large iPhone; verify navigation, dark/light appearance, keyboard dismissal, VoiceOver, accessibility text sizes, loading, and errors.
- [ ] Add XCUITest coverage for synthetic demo navigation, period switching, search, planner edits, sign-out, and reconnection.
  - Source and shared-scheme registration now exist for seven demo cases covering grades/what-if, assignment editing/reset, period/search, school navigation, documents/mail/attachment previews, planner inclusion/reset, and leaving the demo. XCTest compilation/execution and reconnect UI coverage remain pending.
- [ ] Test live sign-in only after explicit authorization with a designated test account supplied outside source control. Never capture real student screenshots or payloads.
- [ ] Validate background/resume, timeout, offline mode, cookie rotation, app-session expiry versus upstream expiry, and account switching against pre-production.
- [ ] Decide whether to support opt-in encrypted record caching and biometric access. Do not introduce password storage implicitly.

## 3. Product parity

- [x] Implement native attendance, calendar, schedule, and student profile with synthetic contracts, in-memory refresh state, and stale-response invalidation. iPhone and live-account verification remain in phase 2.
- [x] Implement native document search, mailbox folder/unread/search filters, on-demand message details and attachments, and native text rendering. Reading does not change StudentVUE's read state. Rich image-only message content still uses an explicit StudentVUE link.
- [x] Implement bounded response streaming, validated PDF/PNG/JPEG/GIF/WebP previews, native iPhone Quick Look, and private temporary-file cleanup on dismissal/sign-out/relaunch. Mac Catalyst type checking and synthetic lifecycle tests pass; iPhone Quick Look and file-protection runtime checks remain in phase 2.
- [x] Port assignment simulation and trend rules from the web grade domain: published precision, weighted/raw separation, exclusions, extra credit, unavailable scales, hidden category reconciliation, edited scores, targets, and chart domains. Native editing/reset and charts compile; web-generated synthetic fixtures pass. iPhone interaction verification remains in phase 2. The rank feature referenced by older handoff notes is absent from the current source and is not a native parity requirement.
- [x] Match the web GPA policy through shared synthetic fixtures, including grade-level eligibility, academic scope, credits, rigor, plus/minus handling, and failing pass/fail outcomes. The policy remains explicitly provisional; district approval is required before describing an estimate as official.
- [x] Implement session/period-scoped in-memory snapshots, bounded to eight periods, safe header validation, full reads after 30 minutes, and forced full explicit refreshes. Missing percentages or changed marks/structure trigger complete retrieval. Automatic refreshes preserve local planner edits. iPhone lifecycle verification remains pending.

## 4. Distribution

- [ ] Choose the final bundle identifier, Apple Developer team, app icon, supported device matrix, and signing settings.
- [ ] Complete privacy disclosures, retention/deletion behavior, vendor and school review, StudentVUE trademark notice, accessibility review, and license/attribution review before distribution. Preserve the repository's AGPL obligations.
- [ ] Set up native CI with an Xcode runner, build/test/archive gates, and secrets stored outside source.
- [ ] Prepare a synthetic reviewer demo, release notes, and TestFlight build. Distribution and production backend changes require a separate user request.

## Architecture and API boundaries

`SwiftUI App → AppModel (@MainActor) → GrademaxxingCore APIClient (serialized) → URLSession (ephemeral) → existing Cloudflare APIs → StudentVUE`

- Session: `POST /api/session`, `GET /api/session/status`, `GET /api/session/keepalive`, `DELETE /api/session`.
- Authenticated reads include `x-grademaxxing-session` and the app's encrypted session cookie; rotated cookies must be captured after every response.
- Gradebook: `GET /api/studentvue/gradebook?reportPeriod=N&fresh=true`. The JSON wraps the existing XML wire contract. No new backend endpoint is necessary.
- Retain district URL/username only as part of the protected session identity; reconnect asks only for the password while that identity is still valid.
- Never follow API redirects with credentials/cookies, log response bodies, embed secrets, or send StudentVUE write operations.
- Show official marks as received. All GPA and what-if results are local estimates with their assumptions shown. The simple category-add calculator refuses mismatched baselines. The assignment planner applies changes relative to its reconstructed baseline and anchors them to the official percentage, labeling missing evidence or baseline disagreement as partial estimates. Invalid edited points make the assignment estimate unavailable.

## Current environment

Swift 6.3.3 and the macOS SDK are available. Full Xcode, `xcodebuild`, `simctl`, and the iOS SDK are not installed. Do not claim an iOS build or simulator visual QA has passed until those tools have run. See `README.md` and `VALIDATION.md` for commands and evidence.
