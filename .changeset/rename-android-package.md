---
"@speedshield/react-native-ssh-sftp": major
---

Renamed the Android native module's Java package from `me.dylankenneally.rnssh` (which also didn't match the directory it lived in, `me/keeex/rnssh`, a leftover from an earlier fork) to `com.speedshield.rnssh`. The native classes were also renamed from `RNSshClientModule`/`RNSshClientPackage` to `RNSSHClientModule`/`RNSSHClientPackage` to match the casing of the JS/iOS bridge module name.

**Consumers must**:

- Update the native module import in `MainApplication.java`/`.kt` from `me.dylankenneally.rnssh.RNSshClientPackage` to `com.speedshield.rnssh.RNSSHClientPackage`.
- Update any ProGuard/R8 keep rules that reference the old package path.

The JS API and the native module bridge name (`RNSSHClient`, used by `NativeModules.RNSSHClient`) are unaffected — this is a native-import-path-only change.
