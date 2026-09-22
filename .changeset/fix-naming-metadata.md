---
"@speedshield/react-native-ssh-sftp": patch
---

Cleaned up naming/metadata inconsistencies left over from this package's fork history:

- Fixed "Spedshield Technologies" typo in `LICENSE`.
- Fixed truncated contributor name in `package.json` ("Bishoy Mikhae" → "Bishoy Mikhael").
- Removed malformed placeholder dependencies (`"-"`, `"D"`) from `package.json` and moved `eslint` to `devDependencies`.
- Updated GitHub issue template auto-assignee from a former maintainer to the current one.
- Updated the `.gitignore` npm-pack tarball pattern to match the current scoped package name.
- Fixed stale Xcode project metadata (`productName`, `ORGANIZATIONNAME`) in `ios/RNSSHClient.xcodeproj`.
