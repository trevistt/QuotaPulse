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
- optional Keychain prompts only when `QUOTA_PULSE_ALLOW_CLAUDE_KEYCHAIN_PROMPT=1`
- override with `QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH`
- override app-owned cache with `QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH`

The public standard launcher and Open at Login installer keep Claude Code Keychain discovery disabled by default. This avoids unattended macOS Keychain prompts, but Claude OAuth quota may appear cached or unavailable until the user runs the attended Keychain launcher or provides credentials explicitly.

## Local Analytics Estimates

QuotaPulse can scan supported local Codex and Claude log metadata read-only to produce secondary local analytics. These analytics are separate from live quota requests.

For Codex, the parser supports usage metadata such as `payload.info.last_token_usage`, `payload.info.total_token_usage` as cumulative deltas only, and `payload.collaboration_mode.settings.model`.

Local analytics snapshots store only aggregate fields such as timestamps, model names, token counts, estimated costs, source labels, and sanitized error messages. They do not store prompt text, response text, message bodies, cookies, Authorization headers, or raw log content.

Cost values are local-log estimates and may differ from official billing, account plans, or invoices.

## Diagnostics Export

The dashboard `Status / Diagnostics` copy action creates a sanitized summary for troubleshooting. It is designed to include provider status, refresh mode, local analytics status, credential mode, and next action without including token values, cookies, Authorization header values, raw credential JSON, raw logs, or full credential paths.

## What QuotaPulse Does Not Do

- No browser cookie access.
- No WebView scraping.
- No background browser automation.
- No sudo installation.
- No system daemon installation.
- No telemetry or analytics SDK.
- No credential writes.
- No OAuth credential refresh.
- No unattended Keychain prompts in the public launcher defaults.
- No raw credential or local-log export from diagnostics copy.
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
