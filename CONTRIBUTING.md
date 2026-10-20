# Contributing to MDMacFanKit

Thanks for helping. Bug fixes, support for more Mac models, sensor naming, UI polish and documentation are all welcome.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Be kind. This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
- Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Building

```bash
swift build                 # debug build of every target
./scripts/build-app.sh      # release build of build/MDMacFanKit.app
```

The project builds with the Command Line Tools alone, and should stay that way:

- **No `@State`.** In recent SDKs `@State` is a macro, and its plugin ships only with Xcode. Use `@StateObject` with `ViewState` (`Sources/MDMacFanKit/Views/ViewState.swift`) for local view state.
- **No other SwiftUI or Observation macros** (`@Observable`, `@Entry`, `#Preview`) for the same reason. Use `ObservableObject` and `@Published`.
- The package uses Swift tools 5.10 with the Swift 5 language mode.

## Testing on real hardware

There is no hardware simulator, so changes that touch the SMC, sensors or the helper must be tried on a real Mac. Say which one in the pull request.

- `mdfan fans` and `mdfan temps` show what the app sees.
- `sudo mdfan set <fan> <rpm>` and `sudo mdfan auto` test fan writes without the app or the helper. **Always finish with `sudo mdfan auto`.**
- After changing the helper, reinstall it from *Settings → Helper → Reinstall Helper…*. If you change the XPC protocol or the helper's behavior, bump `HelperConstants.version` so existing installs are asked to update.
- `MDMacFanKit --snapshot <dir>` renders the menu and settings views to PNG files, which is useful for screenshots in a UI pull request.

When you report a new Mac model, include the model identifier (`sysctl -n hw.model`), the macOS version, and the output of `mdfan fans` and `mdfan temps`.

## Safety rules for the helper

The helper runs as root. Changes to it must keep these guarantees:

- fan speeds are clamped to the fan's own `Mn`/`Mx` limits inside the helper, never only in the app;
- every fan returns to automatic on helper start, on `SIGTERM`, when the last client disconnects, and on heartbeat timeout;
- the XPC interface accepts fan commands only: no arbitrary SMC key writes, no file or process access.

## Code style

- Match the surrounding code: naming, file layout, comment density.
- Comments explain *why*, not *what*.
- Keep pull requests focused. One change per pull request is easier to review than a bundle.

## Commit messages

One line, in English, written as what the commit does. About 50–70 characters, no prefix (`feat:`, `[UI]`), no trailing period:

```text
Add Intel fan mode support through the FS! key
Fix the curve chart clipping at 110 °C
```

Add a short body only when the reason would otherwise be lost, for example a decision that looks wrong without context.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, and check that `swift build` passes with no new warnings.
3. Test on your Mac and describe what you tried in the pull request template.
4. Open the pull request against `main`.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
