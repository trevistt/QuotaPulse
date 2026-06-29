# Architecture

QuotaPulse is a Swift Package with three targets.

## Targets

- `QuotaPulse`: macOS menu bar app, popover UI, optional notch pill, smoke check, and visual QA fixture.
- `QuotaPulseCore`: provider logic, credential source planning, usage snapshots, pacing, scheduling, and redaction helpers.
- `QuotaPulseTestHarness`: executable validation harness for core provider and safety behavior.

## Runtime Flow

1. The app starts as a macOS menu bar utility.
2. `RefreshScheduler` periodically asks usage providers for current quota data.
3. `LocalUsageAnalyticsScheduler` refreshes read-only local analytics stores independently from live quota refreshes.
4. Providers return `UsageSnapshot` values for Codex and Claude.
5. `ProviderOrderStore` loads the persisted Codex/Claude order from `UserDefaults`.
6. UI controllers render compact menu bar status and a taller dashboard popover using the selected provider order.
7. `UsageDiagnosticsFormatter` creates short provider diagnostics and sanitized copy/export text.
8. Errors are converted into sanitized messages before display.

## Smart Refresh

`RefreshScheduler` owns per-provider refresh state for Codex and Claude. Each provider can use its own mode, next refresh time, cooldown, pause reason, auth-blocked reason, and refresh status.

Auto mode can adapt to dashboard visibility, unchanged successful reads, user presence, wake events, Claude OAuth cooldowns, and Claude login repair state. Jitter is applied to scheduled refreshes to avoid fixed polling cadence.

If Claude OAuth returns unauthorized or login-expired, the scheduler records Claude as auth-blocked, keeps any usable stale cached Claude quota, schedules a bounded no-prompt Claude recovery retry, and leaves Codex refresh independent. Automatic Claude refresh is skipped before the retry time; after the retry time, a no-prompt recovery attempt can self-heal if credentials are readable and valid again. A manual repair action remains available for attended owner action.

`UserPresenceMonitor` observes coarse macOS local presence signals and reports them to the scheduler. It does not send presence data anywhere.

`HoverPanelView` renders provider-specific refresh controls and countdown text. Countdown text uses a visible one-second tick while the dashboard is visible or pinned.

The dashboard uses a taller panel size so Overview can show both providers and the fixed footer without clipping the tab bar. Content scrolls only when needed. `StatusItemController` anchors the panel to the visible status item frame, chooses a visible screen frame for multi-screen setups, and repositions the visible panel after content or status item size changes.

Overview order is quota-first: Codex and Claude quota cards render before local analytics, and `Status / Diagnostics` renders after analytics.

## Provider Order

`ProviderOrderStore` persists provider ordering in `UserDefaults` with Codex-first as the default. The selected order is applied to menu bar rows, Overview cards, provider tabs, Smart Refresh rows, accessibility text, smoke checks, and visual QA fixtures.

Changing provider order is display-only. It does not trigger a provider refresh, read Keychain, or enable Claude CLI fallback.

## Provider Model

Codex usage can be read through local OAuth credentials or local CLI/RPC fallback behavior already implemented in the core provider layer.

Claude usage prefers OAuth-compatible local credential sources. Claude Code Keychain discovery is explicit opt-in. Claude login repair uses `ClaudeOAuthPromptGate` to permit one attended Keychain-backed credential read after the dashboard `Fix Claude Login...` action. Claude CLI fallback is also explicit opt-in and is kept separate because it can update local Claude CLI state.

## Local Analytics

`LocalUsageAnalyticsStore` and provider-specific scanners collect aggregate local analytics from supported metadata. Codex parsing supports `payload.info.last_token_usage`, `payload.info.total_token_usage` as cumulative deltas only, and `payload.collaboration_mode.settings.model`.

Local analytics cache aggregate snapshots under the current user's cache folder. They do not cache prompt text, response text, message bodies, Authorization headers, cookies, or raw logs. Cost values are estimates, not official billing.

Overview local analytics renders Today cost, 30d cost, Today tokens, 30d tokens, Latest tokens, Top model, and a compact 14-day histogram for each provider when data exists.

## Diagnostics

`UsageStore` and `LocalUsageAnalyticsStore` track last successful refresh and last sanitized error metadata. `UsageDiagnosticsFormatter` combines quota state, refresh scheduler state, local analytics state, and credential mode into short next-action summaries.

Diagnostics copy/export is intentionally summary-only. It redacts token values, cookies, Authorization headers, auth JSON, and full credential paths before text leaves the dashboard.

## Resources

Brand SVGs live under:

```text
Sources/QuotaPulse/Resources/BrandIcons
```

The icons come from Simple Icons. Review `Sources/QuotaPulse/Resources/BrandIcons/SOURCES.md` and applicable brand guidance before redistributing a packaged app.

## Scripts

- `Scripts/package_app.sh`: builds and packages a local app bundle, ad-hoc signed by default.
- `Scripts/run_practical.sh`: launches the packaged app with public-safe no-Keychain/no-prompt/no-CLI defaults.
- `Scripts/run_practical_keychain_prompt.sh`: launches in attended mode with Keychain prompts explicitly allowed.
- `Scripts/run_practical_claude_cli_fallback.sh`: explicitly enables Claude CLI fallback.
- `Scripts/install_open_at_login.sh`: writes a user LaunchAgent for Open at Login with no-Keychain/no-prompt/no-CLI defaults.
- `Scripts/status_open_at_login.sh`: reports Open at Login and process status.
- `Scripts/uninstall_open_at_login.sh`: removes the user LaunchAgent.
- `Scripts/test.sh`: runs the Swift validation harness.

The `install_launch_agent.sh`, `status_launch_agent.sh`, and `uninstall_launch_agent.sh` scripts are compatibility wrappers around the Open at Login scripts.
