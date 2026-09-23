# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A React Native library (`@speedshield/react-native-ssh-sftp`) that exposes SSH and SFTP functionality to JS via native [Expo Modules](https://docs.expo.dev/modules/overview/), backed by:
- **iOS**: [Citadel](https://github.com/orlandos-nl/Citadel) (pure-Swift SSH/SFTP, built on Apple's own [swift-nio-ssh](https://github.com/apple/swift-nio-ssh)), vendored as a precompiled static XCFramework built from an SPM wrapper package (`ios/XCFrameworkBuild`)
- **Android**: [JSch](https://github.com/mwiede/jsch) (`com.github.mwiede:jsch`) + BouncyCastle

Requires **iOS 18+** — the iOS connection code needs Swift's Task Executor Preference (SE-0417), which needs the iOS 18 Concurrency runtime. No tvOS support.

Published to npm; consuming apps install it and get the native module via Expo autolinking (works from both Expo-managed and bare RN apps — `expo` is an optional peer dependency, `expo-modules-core` a required one).

## Commands

```bash
npm run compile                     # tsc: compiles src/sshclient.ts -> lib/ (this is the "build")
npm run lint                        # eslint .
npm run lint:build                  # eslint with NODE_ENV=production, --max-warnings 20 (used as a pre-compile gate)
npm run build                       # compile + npm pack
./scripts/build-ios-xcframework.sh  # builds ios/RNSSHClientDeps.xcframework from ios/XCFrameworkBuild (needs a Mac + Xcode; run before `npm run build` if the iOS side changed)
```

There is no test suite. There is no single-test command. `.github/workflows/native-build.yml` is the real correctness gate for native code — it scaffolds a throwaway Expo consumer app, installs this package from an actual `npm pack` tarball (not a `file:` link — packing is what catches "files" field packaging bugs a `file:` install wouldn't), and builds the native project through it, for both platforms, on every PR.

To work on the native Android/iOS code directly, you need a consumer React Native app with this package linked — this repo does not contain an example/host app itself (see README's link to a separate example app repo). A reference test app used during the Expo Modules migration is at [longphung/rnssh-test-app](https://github.com/longphung/rnssh-test-app).

## Releasing (Changesets)

Versioning and publishing go through [Changesets](https://github.com/changesets/changesets), not manual `npm version`:

```bash
npm run changeset         # add a changeset describing your change's semver bump (interactive)
npm run version-packages  # apply pending changesets: bumps package.json, writes CHANGELOG.md
npm run release            # compile + `changeset publish` (manual/local publish only — CI publishes via the sub-actions below, not this script)
```

Every PR that should trigger a release needs a changeset file (`.changeset/*.md`). `.github/workflows/release.yml` picks these up on push to `master` and runs as 4 jobs (`select-mode` → `version` or `pack` → `publish`), split specifically so `id-token: write` — needed for npm Trusted Publishing (OIDC, no `NPM_TOKEN`) — is only ever granted to the final `publish` job, per [Changesets' own guidance](https://changesets.dev/guide/automating#trusted-publishing). `select-mode` decides whether there's a pending changeset (→ open/update the "Version Packages" PR) or nothing pending but a publishable version (→ build, pack, and publish, gated behind manual approval on the `production` GitHub Environment). Don't hand-edit the `version` field in `package.json` — let `changeset version` own it.

The same workflow file also supports a manual `workflow_dispatch` run (GitHub UI → Actions → Release → Run workflow, with a `snapshot-tag` input) for [Changesets snapshot releases](https://github.com/changesets/changesets/blob/main/docs/snapshot-releases.md) — publishing a throwaway build under a test dist-tag (e.g. `next`) without touching `master` or committing any version bump. This lives in `release.yml` rather than its own file specifically so it stays covered by the Trusted Publisher registration below (OIDC trust is bound to the exact workflow path).

npm's Trusted Publisher config for this package (npmjs.com → package settings → Trusted Publisher) must have the exact workflow path registered: `SpeedshieldTechnologies/react-native-ssh-sftp`, workflow `release.yml`. If that file gets renamed or moved, the publish job's OIDC token will be rejected until the Trusted Publisher config is updated to match.

There is intentionally no pre-commit git hook (husky was removed) — a local hook running arbitrary shell also runs against commits `changesets/action` makes unattended in CI, which is exactly what broke the release pipeline once. Compile/lint checks happen in CI (`compile.yml`) instead.

## Architecture

### Three-language bridge, one JS API surface

`src/sshclient.ts` is the only JS/TS entry point (compiles to `lib/sshclient.js`, the package's `main`). It defines the public `SSHClient` class and wraps the native module (resolved via `requireNativeModule('RNSSHClient')`, Expo's module registry) with Promise-returning methods, each with an optional Node-style `(error, response)` callback for backwards compatibility — a `callNative()` helper adapts the native Promise to that convention identically on both platforms. All actual SSH/SFTP work happens in native code, both sides using the [Expo Modules DSL](https://docs.expo.dev/modules/module-api/) (`Module`/`definition()`, `AsyncFunction`/`Function`, `Events`/`sendEvent`) instead of the classic RN bridge:

- **Android**: `android/src/main/java/com/speedshield/rnssh/RNSSHClientModule.kt` — a single Kotlin `Module` whose `AsyncFunction`s mirror `sshclient.ts` one-to-one (`connectToHostByPassword`, `execute`, `startShell`, `sftpLs`, etc), backed by JSch. `startShell`'s indefinite blocking read loop still gets its own dedicated `Thread`, same as before the Expo Modules rewrite — Expo's async dispatch pool is shared and shouldn't be starved by a long-lived read loop.
- **iOS**: `ios/RNSSHClientModule.swift` — a Swift `Module` whose `AsyncFunction`s call into `RNSSHClientPool` (`ios/XCFrameworkBuild/Sources/RNSSHClientDeps/RNSSHClientDeps.swift`, compiled into the vendored `RNSSHClientDeps.xcframework`), a Swift `actor` wrapping Citadel. The SSH client is built explicitly on `NIOTSEventLoopGroup` (Network.framework-backed NIO), not the default POSIX-socket event loop — that's the actual fix for connections silently dying on a Wi-Fi/cellular handover, the bug that motivated this rewrite. Every Citadel call that touches the channel's event loop is wrapped to run under Swift's Task Executor Preference (SE-0417); actor-isolation alone does not reliably keep execution on the channel's own NIO queue, which Citadel's internals require.
- Native error rejections on iOS must go through the `RNSSHClientException` subclass at the top of `RNSSHClientModule.swift`, not `Exception`'s own convenience initializer — `Exception.reason` (what JS-visible error messages are actually built from) is a hardcoded ExpoModulesCore bug that the convenience initializer's `description` never reaches.

When adding or changing a method, it must be updated in **three** places to stay working end-to-end: `src/sshclient.ts`, the Android `Module`, and the iOS `Module`. The method name and argument order are expected to line up across all three (Android and iOS take slightly different argument shapes in places — both now split key-based auth into `connectToHostByPassword`/`connectToHostByKey`, matching each other).

### Client identity: the `key` param

There's no single native session object handed back to JS. Instead, `SSHClient.getRandomClientKey()` (TS side) generates a per-instance string key at construction time, and every native call passes that `key` so native code can look up the right session in a pool keyed by that string — a `ConcurrentHashMap<String, SSHClient>` (`clientPool`) on Android, a Swift `[String: ClientState]` dictionary inside the `RNSSHClientPool` actor on iOS. Native "sessions" are addressed purely by this string, not by any object reference JS holds.

### Events (shell output, transfer progress)

Long-running/streaming operations use RN's event emitter rather than callbacks:
- `Shell` — streamed shell output lines
- `DownloadProgress` / `UploadProgress` — SFTP transfer progress (percent, emitted in 5% increments on Android)

Both platforms are Expo Modules, and an Expo Module is already its own `EventEmitter` — `sshclient.ts`'s `registerNativeListener` just calls `RNSSHClient.addListener(...)` directly, with no `NativeEventEmitter`/`DeviceEventEmitter` platform branch (that split existed under the classic RN bridge and no longer applies). Every emitted event includes the originating client's `key` and an event `name`; `SSHClient.handleEvent` filters events by both before invoking the registered handler, since all instances share the same global event channel.

### SFTP directory listing serialization (Android)

`sftpLs` on Android hand-builds JSON strings per file via `String.format` (not a JSON library) and ships them as a list of strings; `sshclient.ts`'s `sftpLs` then `JSON.parse`s each entry after stripping control characters (since filenames/paths can contain bytes that break `JSON.parse`). If you touch this path, keep the hand-rolled format and the TS-side parsing/stripping in sync. This survived the Java→Kotlin rewrite byte-for-byte on purpose.
