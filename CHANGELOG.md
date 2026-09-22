# @speedshield/react-native-ssh-sftp

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
