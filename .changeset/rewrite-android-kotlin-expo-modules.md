---
"@speedshield/react-native-ssh-sftp": major
---

Rewrote the Android native module in Kotlin using the Expo Modules API, replacing the classic `ReactPackage`/`ReactContextBaseJavaModule` registration. JSch remains the underlying SSH/SFTP library and the public JS API is unchanged. One incidental fix: `connectSFTP` no longer marks the stream active on a failed connect.

**Breaking**: the Android toolchain was bumped to what the Expo Modules Gradle plugin requires, and the library now depends on `expo-modules-core` for autolinking (see the iOS changeset in this same release for the full peer dependency change). Consumers need `expo` installed (as an optional dependency purely for autolinking infrastructure if not already using Expo) and their Android toolchain updated accordingly.
