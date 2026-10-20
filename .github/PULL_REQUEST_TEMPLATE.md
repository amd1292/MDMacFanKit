## What does this change?

<!-- One or two sentences. Link the issue if there is one: Fixes #123 -->

## How was it tested?

<!-- Mac model (`sysctl -n hw.model`), macOS version, and what you tried.
     For helper or SMC changes, say whether fans returned to automatic afterwards. -->

## Checklist

- [ ] `swift build` passes without new warnings
- [ ] Tested on a real Mac
- [ ] If the helper's protocol or behavior changed, `HelperConstants.version` is bumped
- [ ] UI changes include a screenshot (`MDMacFanKit --snapshot <dir>` helps)
