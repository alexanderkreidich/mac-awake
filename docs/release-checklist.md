# Mac Awake Release Checklist

Use this before preparing a distributable build.

## Signing and identifiers

- [ ] Confirm the final app bundle identifier.
- [ ] Confirm the final helper bundle identifier / Mach service name.
- [ ] Configure a valid Apple Developer Team ID.
- [ ] Re-enable code signing for app, helper, and testable release products.
- [ ] Verify the helper’s signing requirements match the app’s client-validation logic.

## Privileged helper

- [ ] Choose and document the helper installation API for the target macOS range (`SMJobBless` or the modern `SMAppService`/launch daemon flow).
- [ ] Configure helper entitlements and launchd plist.
- [ ] Install the helper with explicit administrator authorization.
- [ ] Validate incoming XPC requests from the signed app.
- [ ] Confirm the helper exposes only `start`, `cancel`, and `status`.

## Verification

- [ ] Run all unit tests with `xcodebuild`.
- [ ] Verify the built app has `LSUIElement=true`.
- [ ] Launch the app and confirm it has no Dock icon.
- [ ] Confirm the menu contains only:
  - `Keep awake with lid closed`
  - `5 minutes`
  - `30 minutes`
  - `60 minutes`
  - separator
  - `Quit Mac Awake`
- [ ] Start a 5-minute timer and verify the active menu bar/dropdown state, including live countdown updates while the menu remains open.
- [ ] Click the active duration and verify normal sleep behavior is restored.
- [ ] Start a timer, quit the app, and verify restoration occurs before exit.
- [ ] Start a timer and verify expiry restores normal sleep without user action.
- [ ] Perform the closed-lid hardware test on the target Mac.
- [ ] Verify manual recovery works if needed: `sudo pmset -a disablesleep 0`.

## Distribution

- [ ] Archive a release build.
- [ ] Notarize the app if distributing outside the current machine.
- [ ] Staple notarization tickets where applicable.
- [ ] Document installation, uninstallation, and recovery steps for users.
