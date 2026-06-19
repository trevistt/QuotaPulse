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

Package a local unsigned app:

```bash
Scripts/package_app.sh
```

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

## Script Checks

The shell scripts are POSIX `sh` scripts. A basic syntax check can be run with:

```bash
for script in Scripts/*.sh; do sh -n "$script"; done
```

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
