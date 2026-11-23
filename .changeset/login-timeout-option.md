---
"@speedshield/react-native-ssh-sftp": minor
---

Add an optional `{ loginTimeoutMs }` last argument to `connectWithPassword` and `connectWithKey`. On iOS it limits the whole SSH handshake and login (default stays 10 s), through our Citadel fork (`SpeedshieldTechnologies/Citadel` 0.12.1-speedshield.1, which adds `SSHClientSettings.loginTimeout`). On Android it is passed to JSch's `Session.connect(timeout)` (default stays none). A dropbear server whose nameserver doesn't answer spends about 10 s on reverse DNS lookups before its version line, so every iOS login to it failed with "Connect timeout (10 s)" until the timeout could be raised.
