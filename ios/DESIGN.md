<!-- Hallmark · existing native design language / Grademaxxing brand / system chrome -->
# Native design direction

The original SwiftUI app is the design reference. The user liked its design language and wants it retained while making the app recognizably Grademaxxing. Keep the original native visual styling while adapting Grademaxxing’s information layout. This supersedes copying the website’s compact typography and metadata chips.

## Layout and type

- System typography, native page titles, readable course names, and generous spacing follow the original iOS implementation. Outfit remains available for the Grademaxxing wordmark; bundled fonts and their OFL licenses remain intact.
- Gradebook uses simple navy course cards with the official letter on the left, course name and plain period/room/teacher metadata in the middle, and the percentage/disclosure cue on the right. A matching grade bar spans the card below the row; it stays visible on phones at the user’s request. Accessibility text sizes stack the content and preserve a complete spoken summary. The bar is redundant with the spoken percentage and is hidden from accessibility to avoid duplicate announcements.
- Course details retain native grouped lists, ordered closer to Grademaxxing: official grade and metadata, what-if and assignment-planning actions, estimated history, expandable grade categories, then assignments with native filtering and search. Official values remain separate from local estimates.
- An always-visible Gradebook panel shows unweighted and weighted current-course GPA, labeled as a local estimate rather than a transcript GPA. Reporting-period selection and the calculator action share the control row. GPA uses native grouped forms with labeled values, pickers, toggles, and steppers. Attendance, Documents, and Mail also use grouped native lists rather than densely styled web cards.
- Sign-in retains the original large heading and readable fields, with the real brand mark and native buttons. School district is a searchable native picker using the web app’s same offline catalog and ranked name/state/portal matching. It defaults to Pleasanton Unified, preserves portal paths, supports changing/canceling a selection, and keeps an explicit manual HTTPS portal option. Usernames and passwords stay outside the picker. No school behavior or calculation policy is changed by the design restoration.

## Grademaxxing identity

The logo, navy background and surfaces, green and gold grade colors, product terminology, and read-only StudentVUE behavior carry the brand. Native List/Form section rows explicitly use `Theme.surface`, matching Gradebook cards, and their scroll canvas uses `Theme.background`. This includes secondary records, GPA, account, detail and planning sheets; system chrome retains its native appearance. The native app adapts the product to the phone instead of reproducing the website’s dimensions. Dark-only appearance is explicit and remains enforced at the app window, including when the device is in Light Mode.

## Native navigation and accessibility

Four system TabView destinations remain: Grades, Attendance, Documents, and Mail. Each owns an independent NavigationStack. GPA, school tools, and account screens are available through the navigation sheet. System back/edge swipe, toolbars, search, menus, forms, previews, and dialogs retain native behavior. SwiftUI supplies Liquid Glass where supported; no fake glass or opaque bar override is introduced.

Dynamic Type, descriptive official-grade announcements, complete course summaries, native control targets, and decimal-keyboard dismissal remain. Glass is reserved for system chrome. Source assets and previous work are preserved in version history and private development backups.

## Validation boundary

All builds, automated interactions, and captures use invented `--demo` records on the dedicated Grademaxxing Codex Demo simulator. Preserve the other laptop’s API fixes and signing settings. Never run unrelated live-account tests.

See VALIDATION.md for exact results. The primary-screen audit checks contrast, hit regions, descriptions, traits, and clipping. Existing narrowly scoped native-rendering exclusions retain diagnostics: stock search-field clipping, contrast through the native tab-bar scrim, and unmappable nodes only when the last synthetic course row is covered by the bar. They are not accessibility certification. Fully visible app-owned issues remain failures. Physical-device and assistive-technology review remain separate work.

## Apple references

- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Searching](https://developer.apple.com/design/human-interface-guidelines/searching)
- [Accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)

Current limitation: after restoring the native layout, the primary-screen audit still reports one unidentified text-clipping issue. It remains an open failure, not an additional exclusion. See the latest VALIDATION.md entry.
