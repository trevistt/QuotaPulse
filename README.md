# QuotaPulse

> [!IMPORTANT]
> QuotaPulse has been succeeded by [Codex Balance](https://github.com/trevistt/CodexBalance). This repository is archived and remains available for historical reference.

QuotaPulse is a native macOS menu bar utility for checking local Codex and Claude usage at a glance.

It shows compact percentage meters in the macOS menu bar, opens a taller dashboard popover for session, weekly pacing, local-log analytics estimates, and Smart Refresh controls, and can optionally install an Open at Login LaunchAgent for the current user.

Highlights:

- Separate Codex and Claude refresh modes with Auto/manual controls.
- Provider order preference, so the menu bar, Overview cards, provider tabs, Smart Refresh rows, and accessibility label can be Codex-first or Claude-first.
- User-presence aware Smart Refresh pause/slowdown, jitter, Claude rate-limit cooldowns, and visible refresh feedback.
- Read-only local analytics parsing for supported Codex and Claude log metadata, with costs labeled as estimates.
- Status / Diagnostics summaries for refresh state, local analytics state, credential mode, and next action.
- Claude auth recovery states that distinguish healthy quota, stale cached quota, login-needed state, and hard provider errors.
- Public-safe launch defaults that avoid unattended Keychain prompts and keep Claude CLI fallback explicit.

QuotaPulse is a local utility. It is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Existing local Codex and/or Claude authentication, if you want live usage data

## Build

```bash
swift build
swift test
Scripts/test.sh
Scripts/package_app.sh
```

`swift test` builds the SwiftPM core test target. On Command Line Tools-only Macs without an `xctest` runner, SwiftPM may report only `Build complete!`; use `Scripts/test.sh` for explicit local assertion output in that environment.

`Scripts/package_app.sh` creates a local app at:

```text
dist/QuotaPulse.app
```

The default package is ad-hoc signed for local use. It is not Developer ID signed or notarized. macOS may require you to allow the local build manually before opening it.

## Run Locally

After packaging:

```bash
Scripts/run_practical.sh
```

This starts `dist/QuotaPulse.app`, keeps Claude Code Keychain discovery disabled for unattended/no-prompt use, and keeps Claude CLI fallback disabled.

The standard launcher intentionally avoids macOS Keychain prompts. Claude OAuth quota may show cached or unavailable data until you either provide credentials explicitly or run the attended Keychain launcher while you are at the Mac:

```bash
Scripts/run_practical_keychain_prompt.sh
```

QuotaPulse never prompts automatically. The attended launcher starts QuotaPulse in repair mode, and clicking `Fix Claude Login...` is the explicit attended exception when you are ready to approve the macOS Keychain prompt for that launch only.

You can also run the app binary directly for a non-interactive smoke check:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --smoke-check
```

## Smart Refresh

QuotaPulse uses Smart Refresh to keep Codex and Claude usage fresh without polling both providers at the same pace.

- Codex and Claude have separate refresh modes.
- Each provider supports Auto and manual modes.
- Auto mode can slow down when values are unchanged.
- Auto mode pauses or delays automatic refreshes when the Mac is locked, asleep, in screensaver, or idle.
- Jitter is added to avoid fixed polling cadence.
- Claude OAuth rate limits create a cooldown so repeated refreshes do not keep calling Claude before retry time.
- Claude login-expired or unauthorized states schedule a bounded no-prompt background recovery retry, while Codex continues on its own schedule.
- The dashboard shows visible refresh feedback, next refresh countdowns, pause state, and Claude cooldown state.

The dashboard countdown text, such as `Next 24s`, updates while the dashboard is visible or pinned.

## Claude Login Recovery

QuotaPulse treats Claude login-expired or OAuth unauthorized responses as a repairable auth-blocked state instead of repeatedly showing a generic error.

Menu bar states:

- Healthy quota: normal percentage, such as `100%`.
- Stale cached quota: last good percentage with `!`, such as `89!`.
- Claude login blocked without usable cached quota: `--!`.
- Hard unavailable provider error: `ERR`.

When Claude is auth-blocked, Smart Refresh keeps the last cached Claude quota when available, schedules a bounded no-prompt background recovery retry, and skips automatic Claude refresh before that retry time. Codex refresh continues independently. If Claude credentials become readable and valid again before or at the retry, the next recovery attempt can clear the stale auth state.

The dashboard still shows `Fix Claude Login...`; use it only while you are physically at the Mac because it is the explicit attended exception that may trigger a macOS Keychain prompt. If macOS or Claude requires owner action, refresh your Claude Code login, then return to QuotaPulse and press `Fix Claude Login...` or `Refresh`.

The background recovery retry does not enable background Keychain prompts, Claude CLI fallback, browser cookies, WebView login, credential writes, token refresh mutation, or Keychain access-control-list mutation.

## Dashboard Order

The Overview prioritizes core usage before troubleshooting detail:

1. Codex and Claude quota cards
2. Local analytics estimates
3. Status / Diagnostics

This keeps quota status visible first while keeping diagnostics available below analytics.

## Provider Order

The dashboard footer includes an `Order` control. Use it to switch between Codex-first and Claude-first ordering. The choice is saved locally in `UserDefaults` and applies consistently to menu bar rows, Overview cards, provider tabs, Smart Refresh rows, accessibility labels, smoke checks, and visual fixtures.

Changing provider order only changes display order. It does not refresh provider data, read Keychain, or launch Claude CLI.

## Local Analytics Estimates

QuotaPulse can scan supported local Codex and Claude log metadata read-only to show secondary usage analytics. This is separate from live OAuth quota data.

Codex local analytics supports JSONL metadata such as:

- `payload.info.last_token_usage`
- `payload.info.total_token_usage`, interpreted as cumulative deltas only
- `payload.collaboration_mode.settings.model`

QuotaPulse does not print, cache, or expose prompt or message text from local logs. Cost values are estimates based on local metadata and published-style API rate assumptions; they are not official billing records and may differ from your plan or invoice.

Overview local analytics shows Today cost, 30d cost, Today tokens, 30d tokens, Latest tokens, Top model, and a compact 14-day histogram when local metadata exists. Histograms are visible in Overview and are not limited to provider tabs.

## Status / Diagnostics

The dashboard includes a `Status / Diagnostics` section for each provider. It summarizes:

- last successful refresh
- last error category
- current refresh mode and status
- local analytics status
- credential mode
- short next action

Use the diagnostics `Copy` button when you need a safe support summary. The copied text is sanitized and must not include token values, cookies, Authorization header values, full credential JSON, or full credential paths.

## Open at Login

Install or reinstall Open at Login for the current macOS user:

```bash
Scripts/install_open_at_login.sh
```

Check status:

```bash
Scripts/status_open_at_login.sh
```

Uninstall:

```bash
Scripts/uninstall_open_at_login.sh
```

The default LaunchAgent label is:

```text
app.quotapulse.local
```

You can override it when installing:

```bash
QUOTA_PULSE_LAUNCH_AGENT_LABEL=com.example.quotapulse Scripts/install_open_at_login.sh
```

Open at Login uses the same public-safe default as the standard launcher: Claude Keychain discovery is disabled, Keychain prompts are not allowed, and Claude CLI fallback is disabled. Run `Scripts/run_practical_keychain_prompt.sh` manually when you want an attended Keychain refresh.

## Packaging Options

The default local bundle identifier is:

```text
app.quotapulse.local
```

Override it during packaging if you maintain your own app identifier:

```bash
QUOTA_PULSE_BUNDLE_ID=com.example.quotapulse Scripts/package_app.sh
```

Optional packaging variables:

- `QUOTA_PULSE_BUNDLE_ID`
- `QUOTA_PULSE_APP_VERSION`
- `QUOTA_PULSE_APP_BUILD`
- `QUOTA_PULSE_CODESIGN_IDENTITY`
- `QUOTA_PULSE_REQUIRE_CODESIGN`

The default version in the package script is `0.6.0`.

### Local Signing

Packaging ad-hoc signs the app by default. This verifies the app bundle shape for local use, but it is not an official release signature and it is not notarization.

If you have your own local signing identity, you can use it:

```bash
QUOTA_PULSE_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" Scripts/package_app.sh
```

To fail closed when no stable signing identity is configured:

```bash
QUOTA_PULSE_REQUIRE_CODESIGN=1 Scripts/package_app.sh
```

Check the packaged app signing state:

```bash
Scripts/status_signing.sh
```

For official public distribution, use an Apple Developer ID certificate and notarization. Do not commit local signing identity names to this repository.

## Privacy and Security Model

QuotaPulse runs locally on your Mac. It does not include a server component, analytics service, auto-updater, WebView scraping, browser cookie access, background hooks, sudo installation, official release signing, notarization, publishing automation, or GitHub automation.

For live usage data, QuotaPulse reads locally available Codex and Claude credentials from documented local locations, then makes direct API requests from your machine. It does not write credentials, refresh OAuth credentials, or store Authorization header values.

Claude Code Keychain discovery is opt-in through:

```text
QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
```

Keychain prompts are separately gated by:

```text
QUOTA_PULSE_ALLOW_CLAUDE_KEYCHAIN_PROMPT=1
```

The public daily launcher and Open at Login installer do not set either value by default. `Scripts/run_practical_keychain_prompt.sh` sets the launcher-side prompt flag for an attended launch.

The dashboard `Fix Claude Login...` action allows one explicit Keychain-backed Claude credential read for that attended repair attempt. QuotaPulse still does not mutate Keychain access-control lists, write Claude credentials, refresh OAuth credentials, read browser cookies, or capture login through a WebView.

Claude CLI fallback is separate and must be explicitly enabled through the fallback launcher. It may update local Claude CLI state such as `~/.claude.json`, so the normal launcher keeps it disabled.

See [docs/PRIVACY.md](docs/PRIVACY.md) and [docs/SECURITY.md](docs/SECURITY.md).

## Useful Environment Variables

- `QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1`: allow Claude Code Keychain credential discovery.
- `QUOTA_PULSE_ALLOW_CLAUDE_KEYCHAIN_PROMPT=1`: allow a macOS Keychain prompt when Keychain discovery is enabled.
- `QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_KEYCHAIN=1`: ask `Scripts/run_practical.sh` to launch with Keychain discovery enabled.
- `QUOTA_PULSE_LAUNCHER_ALLOW_KEYCHAIN_PROMPT=1`: ask `Scripts/run_practical.sh` to launch with attended Keychain prompts allowed.
- `QUOTA_PULSE_ENABLE_CLAUDE_CLI=1`: enable explicit Claude CLI fallback.
- `QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_CLI=1`: launcher-side confirmation required by the packaged public launcher for Claude CLI fallback.
- `QUOTA_PULSE_SHOW_NOTCH=1`: show the optional secondary notch pill.
- `QUOTA_PULSE_AUTH_PATH=/path/to/auth.json`: override Codex auth file path.
- `QUOTA_PULSE_CODEX_PATH=/path/to/codex`: override Codex CLI path.
- `QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH=/path/to/credentials.json`: override Claude credentials file path.
- `QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH=/path/to/credentials.json`: override app-owned Claude OAuth cache path.
- `QUOTA_PULSE_CLAUDE_CLI_PATH=/path/to/claude`: override Claude CLI path.
- `QUOTA_PULSE_CODESIGN_IDENTITY`: optional local signing identity for packaging.
- `QUOTA_PULSE_REQUIRE_CODESIGN=1`: fail packaging unless `QUOTA_PULSE_CODESIGN_IDENTITY` is set.

Legacy `CODEX_NOTCH_METER_*` environment variable aliases are accepted only as transitional compatibility for older local setups. New configuration should use `QUOTA_PULSE_*`.

## Explicit Claude CLI Fallback

Use this only if OAuth is unavailable and you accept that Claude CLI may update local Claude state:

```bash
Scripts/run_practical_claude_cli_fallback.sh
```

## Visual QA Fixture

Generate a deterministic fixture screenshot without reading live credentials:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --visual-qa-fixture /tmp/quota-pulse-visual-qa.png
```

The output path is your choice. Do not commit screenshots that reveal account details or private usage.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Limitations

- Local build only; no Developer ID signed or notarized release is included.
- No official API guarantee is provided by this repository.
- No auto-update system is included.
- `swift test` includes a deterministic pure-core SwiftPM test target. The broader validation harness remains in `Scripts/test.sh` for explicit assertion output.
- Brand icons are included from Simple Icons; review applicable trademark guidance before redistributing packaged builds.

## License

QuotaPulse is released under the MIT License. See [LICENSE](LICENSE).
