# QuotaPulse

QuotaPulse is a native macOS menu bar utility for checking local Codex and Claude usage at a glance.

It shows compact percentage meters in the macOS menu bar, opens a small dashboard popover for session and weekly pacing, and can optionally install an Open at Login LaunchAgent for the current user.

QuotaPulse is a local utility. It is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Existing local Codex and/or Claude authentication, if you want live usage data

## Build

```bash
swift build
Scripts/test.sh
Scripts/package_app.sh
```

`Scripts/package_app.sh` creates an unsigned local app at:

```text
dist/QuotaPulse.app
```

The app is not signed or notarized. macOS may require you to allow the local build manually before opening it.

## Run Locally

After packaging:

```bash
Scripts/run_practical.sh
```

This starts `dist/QuotaPulse.app`, enables opt-in Claude Code Keychain discovery, and keeps Claude CLI fallback disabled.

You can also run the app binary directly for a non-interactive smoke check:

```bash
dist/QuotaPulse.app/Contents/MacOS/QuotaPulse --smoke-check
```

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

## Privacy and Security Model

QuotaPulse runs locally on your Mac. It does not include a server component, analytics service, auto-updater, WebView scraping, browser cookie access, background hooks, sudo installation, signing, notarization, publishing automation, or GitHub automation.

For live usage data, QuotaPulse reads locally available Codex and Claude credentials from documented local locations, then makes direct API requests from your machine. It does not write credentials, refresh OAuth credentials, or store Authorization header values.

Claude Code Keychain discovery is opt-in through:

```text
QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
```

Claude CLI fallback is separate and must be explicitly enabled. It may update local Claude CLI state such as `~/.claude.json`, so the normal launcher keeps it disabled.

See [docs/PRIVACY.md](docs/PRIVACY.md) and [docs/SECURITY.md](docs/SECURITY.md).

## Useful Environment Variables

- `QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1`: allow Claude Code Keychain credential discovery.
- `QUOTA_PULSE_ENABLE_CLAUDE_CLI=1`: enable explicit Claude CLI fallback.
- `QUOTA_PULSE_SHOW_NOTCH=1`: show the optional secondary notch pill.
- `QUOTA_PULSE_AUTH_PATH=/path/to/auth.json`: override Codex auth file path.
- `QUOTA_PULSE_CODEX_PATH=/path/to/codex`: override Codex CLI path.
- `QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH=/path/to/credentials.json`: override Claude credentials file path.
- `QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH=/path/to/credentials.json`: override app-owned Claude OAuth cache path.
- `QUOTA_PULSE_CLAUDE_CLI_PATH=/path/to/claude`: override Claude CLI path.

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

- Local build only; no signed or notarized release is included.
- No official API guarantee is provided by this repository.
- No auto-update system is included.
- No formal XCTest target is included; the repository includes a Swift test harness executable.
- Brand icons are included from Simple Icons; review applicable trademark guidance before redistributing packaged builds.

## License

QuotaPulse is released under the MIT License. See [LICENSE](LICENSE).
