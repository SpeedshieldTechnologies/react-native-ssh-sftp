# @speedshield/react-native-ssh-sftp

## 3.0.0

### Major Changes

- [#12](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/pull/12) [`b5493b4`](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/commit/b5493b49384c036eed6e8b9763b7551c3c29711b) Thanks [@longphung](https://github.com/longphung)! - Rewrote the Android native module in Kotlin using the Expo Modules API, replacing the classic `ReactPackage`/`ReactContextBaseJavaModule` registration. JSch remains the underlying SSH/SFTP library and the public JS API is unchanged. One incidental fix: `connectSFTP` no longer marks the stream active on a failed connect.

  **Breaking**: the Android toolchain was bumped to what the Expo Modules Gradle plugin requires, and the library now depends on `expo-modules-core` for autolinking (see the iOS changeset in this same release for the full peer dependency change). Consumers need `expo` installed (as an optional dependency purely for autolinking infrastructure if not already using Expo) and their Android toolchain updated accordingly.

- [#12](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/pull/12) [`b5493b4`](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/commit/b5493b49384c036eed6e8b9763b7551c3c29711b) Thanks [@longphung](https://github.com/longphung)! - Rewrote the iOS native module in Swift using the Expo Modules API, replacing NMSSH with [Citadel](https://github.com/orlandos-nl/Citadel) (a pure-Swift SSH/SFTP library built on swift-nio-ssh), vendored as a static XCFramework built at publish time. This fixes SSH connections dropping on a Wi-Fi/cellular network handover: the connection is now explicitly built on `NIOTSEventLoopGroup` (Apple's Network.framework), instead of a plain POSIX-socket event loop that doesn't observe network path changes. `sftpChmod`, `getKeyDetails`, and `generateKeyPair` are now implemented on iOS (previously Android-only or unimplemented); `generateKeyPair` currently supports Ed25519 only.

  **Breaking**:
  - iOS **18.0+** is now required (up from iOS 11) - needed for Swift's Task Executor Preference (SE-0417), which the Citadel-based connection handling relies on for the network-handover fix above.
  - **tvOS support is dropped.**
  - No more manual `Podfile` edit for iOS - resolution is now automatic via the podspec's vendored XCFramework and Expo autolinking. Remove any existing `pod 'NMSSH', ...` line from your `Podfile`.
  - `expo-modules-core` is now a required peer dependency on both platforms (both native modules are Expo Modules now); `expo` itself remains an optional peer dependency, needed only for its autolinking infrastructure in bare React Native apps.

  The public JS API (`SSHClient`'s methods, event names/shapes) is unchanged.

## 2.0.0

### Major Changes

- [#3](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/pull/3) [`a17213c`](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/commit/a17213c8845d21833807e7ab143f3794b795586e) Thanks [@longphung](https://github.com/longphung)! - Renamed the Android native module's Java package from `me.dylankenneally.rnssh` (which also didn't match the directory it lived in, `me/keeex/rnssh`, a leftover from an earlier fork) to `com.speedshield.rnssh`. The native classes were also renamed from `RNSshClientModule`/`RNSshClientPackage` to `RNSSHClientModule`/`RNSSHClientPackage` to match the casing of the JS/iOS bridge module name.

  **Consumers must**:

  - Update the native module import in `MainApplication.java`/`.kt` from `me.dylankenneally.rnssh.RNSshClientPackage` to `com.speedshield.rnssh.RNSSHClientPackage`.
  - Update any ProGuard/R8 keep rules that reference the old package path.

  The JS API and the native module bridge name (`RNSSHClient`, used by `NativeModules.RNSSHClient`) are unaffected — this is a native-import-path-only change.

### Patch Changes

- [#3](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/pull/3) [`a17213c`](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/commit/a17213c8845d21833807e7ab143f3794b795586e) Thanks [@longphung](https://github.com/longphung)! - Cleaned up naming/metadata inconsistencies left over from this package's fork history:

  - Fixed "Spedshield Technologies" typo in `LICENSE`.
  - Fixed truncated contributor name in `package.json` ("Bishoy Mikhae" → "Bishoy Mikhael").
  - Removed malformed placeholder dependencies (`"-"`, `"D"`) from `package.json` and moved `eslint` to `devDependencies`.
  - Updated GitHub issue template auto-assignee from a former maintainer to the current one.
  - Updated the `.gitignore` npm-pack tarball pattern to match the current scoped package name.
  - Fixed stale Xcode project metadata (`productName`, `ORGANIZATIONNAME`) in `ios/RNSSHClient.xcodeproj`.

- [#4](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/pull/4) [`9604d32`](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/commit/9604d324664b4f714ad24031878bdb3e10d3ed46) Thanks [@longphung](https://github.com/longphung)! - Removed husky and its pre-commit hook. It had already been superseded by Changesets for versioning, and its remaining `npm run compile` check was redundant with CI — worse, the hook's non-POSIX shell syntax broke the automated release pipeline, since git hooks also fire on commits made by `changesets/action` in CI.
