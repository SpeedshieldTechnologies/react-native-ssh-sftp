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

There is no test suite (the pre-commit hook has a commented-out `npm test` with a note that current tests "prove nothing"). There is no single-test command.

To work on the native Android/iOS code directly, you need a consumer React Native app with this package linked — this repo does not contain an example/host app itself (see README's link to a separate example app repo).

## Pre-commit behavior (Husky)

`.husky/pre-commit` runs automatically on every commit with local changes and will:
1. Run `npm run compile` and abort the commit if it fails.
2. Auto-bump the patch version in `package.json`/`package-lock.json` via `npm version patch --no-git-tag-version` and `git add` those files.

This means the version number bumps on essentially every commit that touches tracked files — don't manually bump version numbers as part of a change.

## Architecture

### Three-language bridge, one JS API surface

`src/sshclient.ts` is the only JS/TS entry point (compiles to `lib/sshclient.js`, the package's `main`). It defines the public `SSHClient` class and wraps the native module (`NativeModules.RNSSHClient`) with Promise-returning methods, each with an optional Node-style `(error, response)` callback for backwards compatibility. All actual SSH/SFTP work happens in native code:

- **Android**: `android/src/main/java/me/keeex/rnssh/RNSshClientModule.java` — a single `ReactContextBaseJavaModule` exposing `@ReactMethod`s that mirror `sshclient.ts` one-to-one (`connectToHostByPassword`, `execute`, `startShell`, `sftpLs`, etc). Each method spawns its own `new Thread(...)` to do blocking JSch I/O off the RN bridge thread.
- **iOS**: `ios/RNSSHClient.m`/`.h` (the `RCTEventEmitter` bridge module) + `ios/SSHClient.m`/`.h` (a plain Obj-C wrapper around NMSSH). `RNSSHClient` runs on its own serial `dispatch_queue_t`.

When adding or changing a method, it must be updated in **three** places to stay working end-to-end: `src/sshclient.ts`, the Android module, and the iOS module. The method name and argument order are expected to line up across all three (Android and iOS take slightly different argument shapes in places — iOS takes a single `connectToHost` with a `passwordOrKey` union, Android splits this into `connectToHostByPassword`/`connectToHostByKey`).

### Client identity: the `key` param

There's no single native session object handed back to JS. Instead, `SSHClient.getRandomClientKey()` (TS side) generates a per-instance string key at construction time, and every native call passes that `key` so native code can look up the right session in a pool (`clientPool` — a `HashMap`/`NSMutableDictionary` keyed by that string) on both platforms. Native "sessions" are addressed purely by this string, not by any object reference JS holds.

### Events (shell output, transfer progress)

Long-running/streaming operations use RN's event emitter rather than callbacks:
- `Shell` — streamed shell output lines
- `DownloadProgress` / `UploadProgress` — SFTP transfer progress (percent, emitted in 5% increments on Android)

On iOS this goes through `NativeEventEmitter`; on Android through `DeviceEventEmitter` (see the `Platform.OS` branch in `sshclient.ts`'s `registerNativeListener`). Every emitted event includes the originating client's `key` and an event `name`; `SSHClient.handleEvent` filters events by both before invoking the registered handler, since all instances share the same global event channel.

### Known inconsistency: Android package name

The Android native module's Java package is declared as `me.dylankenneally.rnssh` (in `RNSshClientModule.java`, `RNSshClientPackage.java`, and `AndroidManifest.xml`), but the files live under the directory path `android/src/main/java/me/keeex/rnssh/`. This is a leftover from the fork chain (see README credits) — the directory and declared package don't match. Don't "fix" this without checking downstream consumer apps aren't relying on the current package path.

### SFTP directory listing serialization (Android)

`sftpLs` on Android hand-builds JSON strings per file via `String.format` (not a JSON library) and ships them as a `WritableArray` of strings; `sshclient.ts`'s `sftpLs` then `JSON.parse`s each entry after stripping control characters (since filenames/paths can contain bytes that break `JSON.parse`). If you touch this path, keep the hand-rolled format and the TS-side parsing/stripping in sync.
