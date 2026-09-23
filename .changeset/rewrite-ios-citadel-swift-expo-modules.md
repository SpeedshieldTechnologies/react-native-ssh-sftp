---
"@speedshield/react-native-ssh-sftp": major
---

Rewrote the iOS native module in Swift using the Expo Modules API, replacing NMSSH with [Citadel](https://github.com/orlandos-nl/Citadel) (a pure-Swift SSH/SFTP library built on swift-nio-ssh), vendored as a static XCFramework built at publish time. This fixes SSH connections dropping on a Wi-Fi/cellular network handover: the connection is now explicitly built on `NIOTSEventLoopGroup` (Apple's Network.framework), instead of a plain POSIX-socket event loop that doesn't observe network path changes. `sftpChmod`, `getKeyDetails`, and `generateKeyPair` are now implemented on iOS (previously Android-only or unimplemented); `generateKeyPair` currently supports Ed25519 only.

**Breaking**:
- iOS **18.0+** is now required (up from iOS 11) - needed for Swift's Task Executor Preference (SE-0417), which the Citadel-based connection handling relies on for the network-handover fix above.
- **tvOS support is dropped.**
- No more manual `Podfile` edit for iOS - resolution is now automatic via the podspec's vendored XCFramework and Expo autolinking. Remove any existing `pod 'NMSSH', ...` line from your `Podfile`.
- `expo-modules-core` is now a required peer dependency on both platforms (both native modules are Expo Modules now); `expo` itself remains an optional peer dependency, needed only for its autolinking infrastructure in bare React Native apps.

The public JS API (`SSHClient`'s methods, event names/shapes) is unchanged.
