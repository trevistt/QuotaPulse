# Development

## Requirements

- macOS 14 or newer
- Swift 6 toolchain

## Common Commands

Build:

```bash
swift build
```

Run the harness:

```bash
Scripts/test.sh
```

Package a local app:

```bash
Scripts/package_app.sh
```

The default package is ad-hoc signed and uses app version `0.5.0` build `5`.

Run a smoke check against the packaged app:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --smoke-check
```

Generate a deterministic visual QA fixture:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture /tmp/quota-pulse-visual-qa.png
```

Run Swift Package Manager tests:

```bash
swift test
```

This package currently uses the `QuotaPulseTestHarness` executable for validation. `swift test` may report that no tests are found.

## Harness Coverage

`Scripts/test.sh` runs `swift run QuotaPulseTestHarness`. The harness covers provider parsing, redaction, OAuth request behavior, Claude OAuth credential reload, Claude auth-blocked retry pause and repair, Claude rate-limit cooldown, Smart Refresh policy, independent per-provider refresh timing, presence pause/wake behavior, countdown text, refresh debounce, stale cached values, provider ordering, menu bar formatting, local analytics parsing, diagnostics metadata, diagnostics export sanitization, and no-Keychain credential discovery behavior.

The visual QA fixture should also be regenerated when dashboard layout changes:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture /tmp/quota-pulse-public-provider-order-qa.png
```

Additional fixture variants exist for local analytics states:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture-codex-analytics-only /tmp/quota-pulse-codex-analytics-only.png
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture-claude-analytics-error /tmp/quota-pulse-claude-analytics-error.png
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture-no-analytics /tmp/quota-pulse-no-analytics.png
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture-claude-auth-blocked /tmp/quota-pulse-claude-auth-blocked.png
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture-claude-auth-unavailable /tmp/quota-pulse-claude-auth-unavailable.png
```

## Script Checks

The shell scripts are POSIX `sh` scripts. A basic syntax check can be run with:

```bash
for script in Scripts/*.sh; do sh -n "$script"; done
```

## Signing Checks

Check the packaged app signing state:

```bash
Scripts/status_signing.sh
```

Package with a local signing identity:

```bash
QUOTA_PULSE_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" Scripts/package_app.sh
```

Require stable signing and fail closed if no identity is configured:

```bash
QUOTA_PULSE_REQUIRE_CODESIGN=1 Scripts/package_app.sh
```

Do not commit local signing identity names. Official releases should use Developer ID signing and notarization.

## Launcher Defaults

`Scripts/run_practical.sh` and `Scripts/install_open_at_login.sh` are intentionally no-Keychain/no-prompt/no-CLI by default for public builds. This avoids unattended macOS Keychain prompts. Use `Scripts/run_practical_keychain_prompt.sh` only for attended local launches where the user can approve a Keychain prompt, then click `Fix Claude Login...` in the dashboard.

Claude CLI fallback requires the explicit fallback launcher. The app checks both `QUOTA_PULSE_ENABLE_CLAUDE_CLI=1` and the launcher-side `QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_CLI=1` flag so generic shell environment leakage does not silently enable the fallback path.

Do not run `Scripts/install_open_at_login.sh` on a machine that already uses a private/runtime QuotaPulse app unless the owner explicitly wants the public repo login item installed too.

## Public-Safety Checks

Before publishing, scan for:

- local absolute paths
- account emails
- real credentials
- generated build output
- packaged app bundles
- screenshots
- old private project names
- unsupported claims about signing, notarization, distribution, or affiliation
- local signing identity names

Generated directories such as `.build/` and `dist/` are intentionally ignored by git.

## Bundle Identifier

The default packaging bundle identifier is:

```text
app.quotapulse.local
```

Override it locally with:

```bash
QUOTA_PULSE_BUNDLE_ID=com.example.quotapulse Scripts/package_app.sh
```

## Open at Login Label

The default LaunchAgent label is:

```text
app.quotapulse.local
```

Override it locally with:

```bash
QUOTA_PULSE_LAUNCH_AGENT_LABEL=com.example.quotapulse Scripts/install_open_at_login.sh
```
