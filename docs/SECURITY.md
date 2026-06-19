# Security

## Supported Use

QuotaPulse is currently intended for local builds by users who understand their local Codex and Claude authentication setup. The packaged app produced by this repository is unsigned and not notarized.

## Credential Handling

QuotaPulse reads locally available credentials only when needed to request usage data. It does not intentionally write credentials, refresh OAuth credentials, or persist Authorization header values.

Claude Code Keychain discovery is disabled unless explicitly enabled:

```text
QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
```

Claude CLI fallback is disabled by the standard launcher. The explicit fallback launcher warns before enabling it because Claude CLI may update local Claude state.

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
