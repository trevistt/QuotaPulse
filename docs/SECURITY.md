# Security

## Supported Use

QuotaPulse is currently intended for local builds by users who understand their local Codex and Claude authentication setup. The packaged app produced by this repository is ad-hoc signed by default, but it is not Developer ID signed and not notarized.

## Credential Handling

QuotaPulse reads locally available credentials only when needed to request usage data. It does not intentionally write credentials, refresh OAuth credentials, or persist Authorization header values.

Claude Code Keychain discovery is disabled unless explicitly enabled:

```text
QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
```

Interactive macOS Keychain prompts are separately disabled unless explicitly enabled:

```text
QUOTA_PULSE_ALLOW_CLAUDE_KEYCHAIN_PROMPT=1
```

The public `Scripts/run_practical.sh` launcher and Open at Login installer do not enable Keychain discovery, Keychain prompts, or Claude CLI fallback by default. `Scripts/run_practical_keychain_prompt.sh` is the attended launcher for users who are present at the Mac and can approve a Keychain prompt.

When Claude OAuth returns unauthorized or login-expired errors, QuotaPulse marks Claude as auth-blocked, keeps any usable stale cached Claude quota, and schedules a bounded no-prompt background recovery retry. Automatic Claude refresh is skipped before the retry time, and Codex refreshes continue independently.

The background recovery retry does not enable Keychain prompts, Claude CLI fallback, browser cookies, WebView login, credential writes, token refresh mutation, or Keychain access-control-list mutation. The dashboard still shows `Fix Claude Login...`; that action is attended-only and permits one explicit Keychain-backed Claude credential read for the repair attempt.

Claude CLI fallback is disabled by the standard launcher. The explicit fallback launcher warns before enabling it because Claude CLI may update local Claude state.

## Local Signing and Keychain Prompts

Ad-hoc signing is useful for local app bundle validation, but it does not create a stable official release identity. Rebuilding an ad-hoc signed app can change the code identity that macOS Keychain remembers, so macOS may ask again before allowing Claude Code Keychain access.

If you need fewer local Keychain prompts, package with your own local signing identity through `QUOTA_PULSE_CODESIGN_IDENTITY`. This repository does not include or recommend committing any personal signing identity name.

Do not mutate Keychain access-control lists as a workaround. Do not copy or store Claude credentials to bypass Keychain prompts.

Do not add browser cookie access, WebView login capture, token refresh mutation, or background Claude CLI fallback as a repair shortcut.

Official public releases should use Apple Developer ID signing and notarization.

## Local Analytics Boundaries

Local analytics scanning is read-only and designed to aggregate supported usage metadata without exposing prompt or message text. Cost values are estimates from local metadata, not official billing data.

## Diagnostics Export Boundaries

Diagnostics copy/export is for safe troubleshooting summaries only. It must not include token values, cookies, Authorization header values, raw credential JSON, raw local logs, or full credential paths.

## Reporting Security Issues

Until a public repository process is finalized, do not file security-sensitive details in public issues. Contact the repository owner privately with:

- affected version or commit
- reproduction steps
- expected impact
- whether credentials, logs, screenshots, or local paths are involved

Do not include live credentials, account emails, cookies, or Authorization headers in reports.

## Release Boundaries

This repository does not provide:

- signed releases
- notarized releases
- auto-update infrastructure
- hosted telemetry
- remote configuration
- browser session extraction
- WebView login capture

Any future change that adds those capabilities should be reviewed as a security-sensitive design change.
