# Security

## Supported Use

QuotaPulse is currently intended for local builds by users who understand their local Codex and Claude authentication setup. The packaged app produced by this repository is ad-hoc signed by default, but it is not Developer ID signed and not notarized.

## Credential Handling

QuotaPulse reads locally available credentials only when needed to request usage data. It does not intentionally write credentials, refresh OAuth credentials, or persist Authorization header values.

Claude Code Keychain discovery is disabled unless explicitly enabled:

```text
QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
```

Claude CLI fallback is disabled by the standard launcher. The explicit fallback launcher warns before enabling it because Claude CLI may update local Claude state.

## Local Signing and Keychain Prompts

Ad-hoc signing is useful for local app bundle validation, but it does not create a stable official release identity. Rebuilding an ad-hoc signed app can change the code identity that macOS Keychain remembers, so macOS may ask again before allowing Claude Code Keychain access.

If you need fewer local Keychain prompts, package with your own local signing identity through `QUOTA_PULSE_CODESIGN_IDENTITY`. This repository does not include or recommend committing any personal signing identity name.

Do not mutate Keychain access-control lists as a workaround. Do not copy or store Claude credentials to bypass Keychain prompts.

Official public releases should use Apple Developer ID signing and notarization.

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
