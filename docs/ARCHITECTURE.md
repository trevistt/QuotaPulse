# Architecture

QuotaPulse is a Swift Package with three targets.

## Targets

- `QuotaPulse`: macOS menu bar app, popover UI, optional notch pill, smoke check, and visual QA fixture.
- `QuotaPulseCore`: provider logic, credential source planning, usage snapshots, pacing, scheduling, and redaction helpers.
- `QuotaPulseTestHarness`: executable validation harness for core provider and safety behavior.

## Runtime Flow

1. The app starts as a macOS menu bar utility.
2. `RefreshScheduler` periodically asks usage providers for current data.
3. Providers return `UsageSnapshot` values for Codex and Claude.
4. UI controllers render compact menu bar status and a dashboard popover.
5. Errors are converted into sanitized messages before display.

## Smart Refresh

`RefreshScheduler` owns per-provider refresh state for Codex and Claude. Each provider can use its own mode, next refresh time, cooldown, pause reason, and refresh status.

Auto mode can adapt to dashboard visibility, unchanged successful reads, user presence, wake events, and Claude OAuth cooldowns. Jitter is applied to scheduled refreshes to avoid fixed polling cadence.

`UserPresenceMonitor` observes coarse macOS local presence signals and reports them to the scheduler. It does not send presence data anywhere.

`HoverPanelView` renders provider-specific refresh controls and countdown text. Countdown text uses a visible one-second tick while the dashboard is visible or pinned.

## Provider Model

Codex usage can be read through local OAuth credentials or local CLI/RPC fallback behavior already implemented in the core provider layer.

Claude usage prefers OAuth-compatible local credential sources. Claude Code Keychain discovery is explicit opt-in. Claude CLI fallback is also explicit opt-in and is kept separate because it can update local Claude CLI state.

## Resources

Brand SVGs live under:

```text
Sources/QuotaPulse/Resources/BrandIcons
```

The icons come from Simple Icons. Review `Sources/QuotaPulse/Resources/BrandIcons/SOURCES.md` and applicable brand guidance before redistributing a packaged app.

## Scripts

- `Scripts/package_app.sh`: builds and packages an unsigned local app bundle.
- `Scripts/run_practical.sh`: launches the packaged app with practical local defaults.
- `Scripts/run_practical_claude_cli_fallback.sh`: explicitly enables Claude CLI fallback.
- `Scripts/install_open_at_login.sh`: writes a user LaunchAgent for Open at Login.
- `Scripts/status_open_at_login.sh`: reports Open at Login and process status.
- `Scripts/uninstall_open_at_login.sh`: removes the user LaunchAgent.
- `Scripts/test.sh`: runs the Swift validation harness.

The `install_launch_agent.sh`, `status_launch_agent.sh`, and `uninstall_launch_agent.sh` scripts are compatibility wrappers around the Open at Login scripts.
