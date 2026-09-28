---
"@speedshield/react-native-ssh-sftp": patch
---

Fixed the iOS build failing with `No such module 'RNSSHClientDeps'`: 3.0.0 was published without `ios/RNSSHClientDeps.xcframework`, because the release job ran on Linux and never built it. Releases now build the XCFramework on macOS and fail if it's missing from the packed tarball.
