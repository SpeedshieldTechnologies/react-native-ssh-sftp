---
"@speedshield/react-native-ssh-sftp": patch
---

Rewrote the iOS native module in Swift using the Expo Modules API, replacing NMSSH with [Citadel](https://github.com/orlandos-nl/Citadel) (a pure-Swift SSH/SFTP library built on swift-nio-ssh), vendored as a static XCFramework built at publish time. This fixes SSH connections dropping on a Wi-Fi/cellular network handover: the connection is now explicitly built on `NIOTSEventLoopGroup` (Apple's Network.framework), instead of a plain POSIX-socket event loop that doesn't observe network path changes. `sftpChmod`, `getKeyDetails`, and `generateKeyPair` are now implemented on iOS (previously Android-only or unimplemented); `generateKeyPair` currently supports Ed25519 only. iOS 17+ is now required (from iOS 11), and tvOS support is dropped. The public JS API is unchanged.
