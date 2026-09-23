---
"@speedshield/react-native-ssh-sftp": patch
---

Rewrote the Android native module in Kotlin using the Expo Modules API, replacing the classic `ReactPackage`/`ReactContextBaseJavaModule` registration. JSch remains the underlying SSH/SFTP library and the public JS API is unchanged. One incidental fix: `connectSFTP` no longer marks the stream active on a failed connect.
