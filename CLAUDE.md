# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A React Native library (`@speedshield/react-native-ssh-sftp`) that exposes SSH and SFTP functionality to JS via a native module, backed by:
- **iOS**: [NMSSH](https://github.com/aanah0/NMSSH) (a fork, pulled via the consuming app's `Podfile`, not this repo's)
- **Android**: [JSch](https://github.com/mwiede/jsch) (`com.github.mwiede:jsch`) + BouncyCastle + Jackson

Published to npm; consuming apps install it and link the native module (autolinking, no manual linking needed since RN 0.73+).

## Commands

```bash
npm run compile      # tsc: compiles src/sshclient.ts -> lib/ (this is the "build")
npm run lint         # eslint .
npm run lint:build    # eslint with NODE_ENV=production, --max-warnings 20 (used as a pre-compile gate)
npm run build         # compile + npm pack
```

There is no test suite. There is no single-test command.

To work on the native Android/iOS code directly, you need a consumer React Native app with this package linked — this repo does not contain an example/host app itself (see README's link to a separate example app repo).

## Releasing (Changesets)

Versioning and publishing go through [Changesets](https://github.com/changesets/changesets), not manual `npm version`:

```bash
npm run changeset         # add a changeset describing your change's semver bump (interactive)
npm run version-packages  # apply pending changesets: bumps package.json, writes CHANGELOG.md
npm run release            # compile + `changeset publish` (manual/local publish only — CI publishes via the sub-actions below, not this script)
```

Every PR that should trigger a release needs a changeset file (`.changeset/*.md`). `.github/workflows/release.yml` picks these up on push to `master` and runs as 4 jobs (`select-mode` → `version` or `pack` → `publish`), split specifically so `id-token: write` — needed for npm Trusted Publishing (OIDC, no `NPM_TOKEN`) — is only ever granted to the final `publish` job, per [Changesets' own guidance](https://changesets.dev/guide/automating#trusted-publishing). `select-mode` decides whether there's a pending changeset (→ open/update the "Version Packages" PR) or nothing pending but a publishable version (→ build, pack, and publish, gated behind manual approval on the `production` GitHub Environment). Don't hand-edit the `version` field in `package.json` — let `changeset version` own it.

npm's Trusted Publisher config for this package (npmjs.com → package settings → Trusted Publisher) must have the exact workflow path registered: `SpeedshieldTechnologies/react-native-ssh-sftp`, workflow `release.yml`. If that file gets renamed or moved, the publish job's OIDC token will be rejected until the Trusted Publisher config is updated to match.

There is intentionally no pre-commit git hook (husky was removed) — a local hook running arbitrary shell also runs against commits `changesets/action` makes unattended in CI, which is exactly what broke the release pipeline once. Compile/lint checks happen in CI (`compile.yml`) instead.

## Architecture

### Three-language bridge, one JS API surface

`src/sshclient.ts` is the only JS/TS entry point (compiles to `lib/sshclient.js`, the package's `main`). It defines the public `SSHClient` class and wraps the native module (`NativeModules.RNSSHClient`) with Promise-returning methods, each with an optional Node-style `(error, response)` callback for backwards compatibility. All actual SSH/SFTP work happens in native code:

- **Android**: `android/src/main/java/com/speedshield/rnssh/RNSSHClientModule.java` — a single `ReactContextBaseJavaModule` exposing `@ReactMethod`s that mirror `sshclient.ts` one-to-one (`connectToHostByPassword`, `execute`, `startShell`, `sftpLs`, etc). Each method spawns its own `new Thread(...)` to do blocking JSch I/O off the RN bridge thread.
- **iOS**: `ios/RNSSHClient.m`/`.h` (the `RCTEventEmitter` bridge module) + `ios/SSHClient.m`/`.h` (a plain Obj-C wrapper around NMSSH). `RNSSHClient` runs on its own serial `dispatch_queue_t`.

When adding or changing a method, it must be updated in **three** places to stay working end-to-end: `src/sshclient.ts`, the Android module, and the iOS module. The method name and argument order are expected to line up across all three (Android and iOS take slightly different argument shapes in places — iOS takes a single `connectToHost` with a `passwordOrKey` union, Android splits this into `connectToHostByPassword`/`connectToHostByKey`).

### Client identity: the `key` param

There's no single native session object handed back to JS. Instead, `SSHClient.getRandomClientKey()` (TS side) generates a per-instance string key at construction time, and every native call passes that `key` so native code can look up the right session in a pool (`clientPool` — a `HashMap`/`NSMutableDictionary` keyed by that string) on both platforms. Native "sessions" are addressed purely by this string, not by any object reference JS holds.

### Events (shell output, transfer progress)

Long-running/streaming operations use RN's event emitter rather than callbacks:
- `Shell` — streamed shell output lines
- `DownloadProgress` / `UploadProgress` — SFTP transfer progress (percent, emitted in 5% increments on Android)

On iOS this goes through `NativeEventEmitter`; on Android through `DeviceEventEmitter` (see the `Platform.OS` branch in `sshclient.ts`'s `registerNativeListener`). Every emitted event includes the originating client's `key` and an event `name`; `SSHClient.handleEvent` filters events by both before invoking the registered handler, since all instances share the same global event channel.

### SFTP directory listing serialization (Android)

`sftpLs` on Android hand-builds JSON strings per file via `String.format` (not a JSON library) and ships them as a `WritableArray` of strings; `sshclient.ts`'s `sftpLs` then `JSON.parse`s each entry after stripping control characters (since filenames/paths can contain bytes that break `JSON.parse`). If you touch this path, keep the hand-rolled format and the TS-side parsing/stripping in sync.
