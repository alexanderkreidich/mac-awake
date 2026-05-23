# Lid Awake Menu Bar App Design

Date: 2026-05-23
Project directory: `/Users/sasha/Projects/lid-awake`
Visual reference: `/Users/sasha/Documents/mockups/lid-awake-menubar/2026-05-23-menu-state-preview-v3.html`

## Summary

Build a small Swift macOS menu bar app named **Lid Awake**. The app lets the user keep a Mac awake while the lid is closed and no external monitor is connected. The dropdown offers exactly three timed choices: **5 minutes**, **30 minutes**, and **60 minutes**.

When a timer is active, the selected duration is highlighted/checkmarked and the menu bar icon shows the active duration or remaining time. Clicking the active duration again cancels it and restores normal sleep behavior. The menu must not include a separate `Status Off` row or a separate cancel row.

Because true lid-closed/no-monitor awake mode cannot be handled reliably with normal `IOPMAssertion`/`caffeinate` APIs, the app will use privileged control of macOS sleep settings and will require administrator authorization.

## Goals

- Provide a macOS menu bar-only Swift app.
- Let the user choose one of three durations: 5, 30, or 60 minutes.
- Keep the Mac awake even when the lid is closed with no external monitor attached.
- Show the active timer clearly in both the menu bar and dropdown.
- Cancel by clicking the already-active duration again.
- Restore the previous sleep behavior when the timer expires, when cancelled, or before the app quits.
- Keep the first version intentionally small: no preferences window, no custom schedules, no indefinite mode.

## Non-goals

- No App Store distribution for the first version.
- No iOS/iPadOS support.
- No indefinite keep-awake mode.
- No background analytics or networking.
- No unrelated system power-management settings.
- No `Status Off` menu row.

## Approaches Considered

### Recommended: menu bar app + privileged helper

The Swift menu bar app owns the user interface. A small privileged helper owns the sleep-setting changes. The helper exposes a narrow XPC API for starting, cancelling, and reading the current timer state.

Pros:
- Can restore normal sleep automatically when the timer expires, even without another admin prompt.
- Avoids running arbitrary shell commands from the UI process.
- Keeps privileged behavior isolated and auditable.
- Best fit for true lid-closed/no-monitor mode.

Cons:
- More setup than a single-process menu bar utility.
- Requires code signing during development and a helper installation flow.

### Simpler prototype: AppleScript admin prompt around `pmset`

The app could run `pmset` through a macOS administrator prompt each time it needs to change sleep settings.

Pros:
- Fastest prototype.
- Less project structure.

Cons:
- Timer expiry may happen while the lid is closed, when the user cannot approve another admin prompt.
- Repeated prompts are annoying.
- Less robust after crashes or app termination.

This approach is acceptable only for a throwaway proof of concept, not for the intended timer behavior.

### Rejected: `IOPMAssertion` or `caffeinate` only

These APIs can prevent idle sleep while the lid is open, but they do not reliably override the forced sleep behavior caused by closing the lid with no external monitor. This does not meet the core requirement.

## User Experience

### Menu bar item

Inactive:
- Shows a compact app icon and label such as `Awake`.

Active:
- Shows the active duration or countdown, such as `30m` or `24m`.
- Uses an active visual state so it is obvious the Mac is being kept awake.

### Dropdown

The dropdown contains:

1. A small title: `Keep awake with lid closed`
2. `5 minutes`
3. `30 minutes`
4. `60 minutes`
5. Separator
6. `Quit Lid Awake`

When active:
- The active duration row is highlighted and checkmarked.
- The active row may show remaining time on the trailing edge, for example `24:12 left`.
- Clicking the highlighted active row cancels the timer.
- Clicking a different duration switches to that duration and updates the timer.

The dropdown does not include `Status Off` and does not include a separate cancel menu item.

### First-run safety notice

On the first attempt to start a timer, show a short native alert before requesting admin permission:

> Lid Awake can keep your Mac running while closed. Use it only when the Mac has ventilation and enough battery or power. Normal sleep will be restored when the timer ends or when you cancel it.

The alert has:
- `Continue`
- `Cancel`

After the user continues, the app starts the privileged helper installation or authorization flow.

## System Behavior

The implementation will use the macOS `pmset disablesleep` setting through the privileged helper:

- Enable: `/usr/bin/pmset -a disablesleep 1`
- Restore: `/usr/bin/pmset -a disablesleep <previous value>`

Before enabling, the helper reads the current `disablesleep` value and stores it as the previous value for the active session. Restoration returns the setting to that previous value, not blindly to `0`, so the app does not overwrite a pre-existing user/system configuration.

The helper accepts only the supported durations: 300, 1800, and 3600 seconds.

## Architecture

### Components

#### `LidAwakeApp`

SwiftUI app entry point. Creates the menu bar scene and shared app state.

#### `MenuBarController`

Renders the `MenuBarExtra` dropdown and maps menu clicks to app actions.

Responsibilities:
- Display the inactive and active menu bar labels.
- Render the three duration rows.
- Highlight/checkmark the active duration.
- Send start, switch, cancel, and quit actions to the app state.

#### `AwakeTimerStore`

Main-process observable state used by the UI.

Responsibilities:
- Hold current timer state returned by the helper.
- Drive countdown display updates.
- Poll or subscribe to helper status changes.
- Keep UI state consistent after app launch.

#### `SleepControlClient`

XPC client wrapper used by the app process.

Responsibilities:
- Connect to the privileged helper.
- Request helper installation/authorization when needed.
- Expose typed methods: `start(duration:)`, `cancel()`, and `status()`.
- Convert helper errors into user-facing messages.

#### `LidAwakeHelper`

Privileged helper with a minimal XPC API.

Responsibilities:
- Validate requests come from the signed app.
- Accept only supported durations.
- Read current `pmset disablesleep` state.
- Enable lid-closed awake mode.
- Persist active session state.
- Restore previous sleep behavior on cancel, expiry, or quit request.
- Report current status to the app.

#### `SessionState`

Persisted helper-owned state stored under a root-writable application support path.

Fields:
- `isActive`
- `durationSeconds`
- `startedAt`
- `expiresAt`
- `previousDisableSleepValue`

The helper uses this state to recover after restart. If it starts and finds an expired active session, it restores the previous sleep value immediately.

## Data Flow

### Start a timer

1. User selects `5 minutes`, `30 minutes`, or `60 minutes`.
2. App shows the first-run safety notice if needed.
3. App calls `SleepControlClient.start(duration:)`.
4. Helper validates the duration.
5. Helper reads and stores the previous `disablesleep` value.
6. Helper runs `pmset -a disablesleep 1`.
7. Helper stores the active session with an expiry time.
8. Helper schedules restoration at expiry.
9. App updates the menu bar and dropdown to the active state.

### Click the active duration again

1. User clicks the highlighted/checkmarked duration.
2. App calls `SleepControlClient.cancel()`.
3. Helper restores the previous `disablesleep` value.
4. Helper clears active session state.
5. App returns to the inactive menu bar label.

### Switch durations

1. User clicks a different duration while a timer is active.
2. App calls `SleepControlClient.start(duration:)` with the new duration.
3. Helper keeps the original previous `disablesleep` value.
4. Helper replaces the active expiry time and duration.
5. UI highlights the new active duration.

### Timer expires

1. Helper timer reaches `expiresAt`.
2. Helper restores the previous `disablesleep` value.
3. Helper clears active session state.
4. App observes/polls status and returns to inactive display.

### Quit

1. User selects `Quit Lid Awake`.
2. If a timer is active, app asks helper to cancel first.
3. App quits after cancellation succeeds or after showing a clear error if restoration fails.

## Error Handling

- If helper installation fails, show a native alert explaining that admin permission is required.
- If `pmset` is unavailable or rejects `disablesleep`, show an unsupported-system alert and do not mark the timer active.
- If enabling succeeds but state persistence fails, immediately restore the previous `disablesleep` value and show an error.
- If restoration fails, keep the app running, show an alert with the manual recovery command, and keep the active state visible until restored.
- Manual recovery command shown on restore failure:
  - `sudo pmset -a disablesleep 0`

## Security Model

- The app process is not privileged.
- The helper exposes only typed XPC methods for supported actions.
- The helper never accepts arbitrary shell text from the app.
- `pmset` is invoked with fixed executable path and fixed argument lists.
- The helper validates the client code signature before accepting requests.
- Session state is stored in a root-writable location to prevent non-privileged tampering.

## Project Structure

Planned structure:

```text
lid-awake/
  AGENTS.md
  docs/
    superpowers/
      specs/
        2026-05-23-lid-awake-menubar-design.md
  LidAwake/
    LidAwakeApp.swift
    MenuBarController.swift
    AwakeTimerStore.swift
    SleepControlClient.swift
  LidAwakeHelper/
    HelperMain.swift
    SleepControlService.swift
    SessionState.swift
    PMSetClient.swift
  LidAwakeTests/
    AwakeTimerStoreTests.swift
    MenuRenderingStateTests.swift
  LidAwakeHelperTests/
    SessionStateTests.swift
    PMSetClientTests.swift
```

The implementation should avoid adding files until they are needed for the first working vertical slice.

## Testing Plan

### Unit tests

- Duration selection maps only to 300, 1800, and 3600 seconds.
- Clicking inactive duration starts that duration.
- Clicking active duration cancels.
- Clicking different duration switches timer.
- Remaining-time formatting is stable.
- Session state restores previous `disablesleep` value.
- Expired session on helper launch triggers restoration.

### Integration tests with test doubles

- App UI state updates from fake helper status.
- Helper calls a fake `PMSetClient` with the expected fixed arguments.
- Restore failure keeps active/error state visible.

### Manual system checks

- Start 5-minute timer and verify active UI state.
- Close lid with no external monitor and verify the machine remains reachable/running for the timer duration.
- Confirm normal sleep behavior returns after expiry.
- Confirm clicking the active duration cancels and restores sleep behavior.
- Confirm quitting while active restores before exit.

## Success Criteria

- The app launches as a menu bar-only macOS app.
- The dropdown has only the title, three duration choices, separator, and quit item.
- No `Status Off` row appears.
- Starting a duration enables lid-closed awake mode.
- Active duration is highlighted/checkmarked.
- Clicking the active duration cancels.
- Timer expiry restores the previous sleep behavior without needing user interaction at that moment.
- Quit restores previous sleep behavior before the process exits.
