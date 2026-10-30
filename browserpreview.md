# Free native iPhone preview in Codex

Use [serve-sim](https://github.com/EvanBacon/serve-sim), an Apache-2.0 open-source tool. It serves the real Apple Simulator through a local browser page, with taps, swipes, typing, and logs. It has no hosted-service minute allowance and supports native SwiftUI apps.

The simulator host still needs full Xcode and an installed iOS runtime. Command Line Tools alone are insufficient. The viewing computer only needs browser access to the host. This does not translate SwiftUI into HTML or substitute a macOS layout for the iPhone UI.

## On the Xcode laptop

From this repository, run:

```sh
bash ios/scripts/preview-browser.sh
```

Requires Node.js 20+ and Python 3. The script selects an available iPhone (preferring one already booted), builds and installs Grademaxxing, relaunches it with `--demo`, and starts a loopback-only server. You may pass a specific iPhone simulator UDID as the first argument. Build products stay under the ignored `ios/.build/` directory. The first run downloads pinned `serve-sim@0.1.48` from npm.

Open **http://127.0.0.1:3200** in Codex's browser on that laptop. You can interact with the actual iPhone app while keeping the code beside it. On Xcode 27, keyboard input may require the simulator's Device Hub window to be visible/frontmost and an Accessibility permission prompt to be handled by the laptop's user.

## View from this Mac

If SSH access to the Xcode laptop is already configured, forward the port here:

```sh
ssh -N -L 3200:127.0.0.1:3200 your-user@your-xcode-laptop
```

Then open **http://127.0.0.1:3200** in this Mac's Codex browser. Keep the preview bound to loopback: serve-sim also has a shell-execution feature, so it should not be exposed publicly. No Appetize account or upload is needed. Stop the server and tunnel with Ctrl-C when finished.

The launcher always uses invented demo records. Keep UI tests and visual captures synthetic. This stream supports interactive checks; use the ten synthetic XCUITests for repeatable assertions.

## Verified setup — October 16, 2026

- The GitHub checkout is synced to `a129864`. The Xcode laptop also has newer uncommitted changes; its working copy is the source for the running preview and those changes were preserved. Nine portable tracked source/documentation files have also been imported into this Mac and verified byte for byte. Machine-specific project changes, workspace state, and untracked account-test files were excluded. GitHub publication is pending the requested sync scope.
- This Mac's prior SwiftUI macOS build passed. After importing the other laptop's tracked source changes, all 75 synthetic core checks, Swift formatting, project generation, and diff checks pass here. The remote working copy also passes 75 synthetic core checks.
- The remote Xcode 27.1 run also passes all seven synthetic UI cases: 7 passed, 0 failed, 0 skipped, confirmed from its xcresult summary. The demo is relaunched after the suite.
- This Mac has no full Xcode installation. The Xcode laptop supplies Xcode 27.1 and the iOS 27.0 runtime. Its required CoreSimulator component update was installed successfully.
- A dedicated **Grademaxxing Codex Demo** iPhone simulator runs the app with `--demo`. Its actual picture is streamed through serve-sim and a private SSH tunnel to **http://127.0.0.1:3200** in this Mac's Codex browser. A browser tap successfully opened AP Calculus and a keyboard key appeared in its search field, verifying touch and keyboard input as well as video.
- The server is bound to loopback. The tunnel runs independently of the terminal session, and the remote Mac is kept awake while the preview process runs.
- Connection metadata is stored locally in the ignored `ios/.build/codex-remote/connection.json`; the remote launcher, logs, and simulator identity are in the remote checkout's ignored `ios/.build/codex-preview/` directory. No password is stored in those files.

Other open-source choices include [simmer](https://github.com/joshdholtz/simmer), a broader simulator dashboard, and [tapflow](https://github.com/jo-duchan/tapflow), a multi-user self-hosted relay. serve-sim is the smallest fit for a local Codex preview.

## Native visual parity follow-up

The native UI now follows the established web branding, fonts, Gradebook hierarchy, and four primary mobile destinations. See `ios/DESIGN.md`. The updated run passes all eight synthetic UI cases (0 failures/skips); Gradebook and course layouts were inspected at normal and largest accessibility text size, then the original text size was restored. Evidence is recorded in `ios/VALIDATION.md`. Source changes are present on both Macs; GitHub publication remains pending the requested sync scope.

The subsequent mobile refinement matches the web’s phone row columns, type sizes, compact controls, and course hierarchy more closely. Its full eight-case simulator suite passes; see the dated evidence in `ios/VALIDATION.md`.


## Apple native navigation follow-up

The current preview uses Apple’s system TabView and NavigationStack, with native Liquid Glass on supported OS versions. The four tab histories are preserved, and back navigation, toolbar actions, scoped search, and light/dark appearance use native behavior. The full dedicated-simulator suite passes 10 synthetic cases; its accessibility checks have explicit documented native-rendering exclusions. See DESIGN.md and VALIDATION.md under ios/ for scope and evidence.

Current appearance policy: **dark-only**, explicitly requested by the user. The app remains dark when the simulator/device uses Light Mode; keep this policy when making later UI changes.
