---
"@speedshield/react-native-ssh-sftp": patch
---

Removed husky and its pre-commit hook. It had already been superseded by Changesets for versioning, and its remaining `npm run compile` check was redundant with CI — worse, the hook's non-POSIX shell syntax broke the automated release pipeline, since git hooks also fire on commits made by `changesets/action` in CI.
