# Privacy

QuotaPulse is designed as a local macOS utility. It does not send usage data to a QuotaPulse server because there is no QuotaPulse server component.

## Data Access

QuotaPulse can read local Codex and Claude authentication material from documented local locations so it can request usage data directly from the relevant provider.

Codex defaults:

- `~/.codex/auth.json`
- override with `QUOTA_PULSE_AUTH_PATH`

Claude defaults:

- `~/.claude/.credentials.json`
- app-owned cache under the current user's Application Support folder
- optional Claude Code Keychain discovery when `QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1`
- override with `QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH`
- override app-owned cache with `QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH`

## What QuotaPulse Does Not Do

- No browser cookie access.
- No WebView scraping.
- No background browser automation.
- No sudo installation.
- No system daemon installation.
- No telemetry or analytics SDK.
- No credential writes.
- No OAuth credential refresh.
- No GitHub automation.
- No notarization or publishing workflow.

## User Presence

Smart Refresh can use coarse local macOS presence signals to pause or slow automatic refreshes. It observes states such as active, idle, locked, screensaver, asleep, or suspended. These states stay local and are used only to schedule refreshes.

## Logs

The practical launcher writes local logs under:

```text
~/Library/Logs/QuotaPulse
```

Do not share logs publicly unless you have reviewed them for private paths, account details, and errors. Runtime error messages are sanitized to reduce accidental credential disclosure, but logs should still be treated as local diagnostic files.

## Claude CLI Fallback

Claude CLI fallback is disabled by default. If enabled explicitly, it may update local Claude CLI state such as:

```text
~/.claude.json
```

Use it only if you understand and accept that local side effect.

## Keychain Prompts

Unsigned or ad-hoc signed local builds may cause macOS to ask for Keychain access again after rebuilds because the app identity may change. Stable local signing can reduce repeated prompts, but official public distribution should use Developer ID signing and notarization. QuotaPulse does not change Keychain access-control lists and does not copy Claude credentials as a workaround.

## Screenshots

Do not commit screenshots that show account emails, exact private usage, private paths, or other sensitive local details.
