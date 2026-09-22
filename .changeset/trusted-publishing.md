---
"@speedshield/react-native-ssh-sftp": patch
---

Switched the release workflow to npm Trusted Publishing (OIDC) — no `NPM_TOKEN` secret needed anymore. Split `.github/workflows/release.yml` into separate `select-mode` / `version` / `pack` / `publish` jobs so that `id-token: write` (required for trusted publishing) is only ever granted to the job that actually publishes, per Changesets' own guidance. The publish job requires manual approval via the `production` GitHub Environment.

**Requires a one-time setup step on npmjs.com**: configure a Trusted Publisher for this package pointing at `SpeedshieldTechnologies/react-native-ssh-sftp`, workflow `release.yml`.
