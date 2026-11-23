---
"@speedshield/react-native-ssh-sftp": patch
---

iOS: allow 30 s from connect to logged in instead of Citadel's fixed 10 s, using our Citadel fork (`SpeedshieldTechnologies/Citadel` 0.12.1-speedshield.1, which adds `SSHClientSettings.loginTimeout`). A dropbear server whose nameserver doesn't answer spends about 10 s on reverse DNS lookups before its version line, so every iOS login to it failed with "Connect timeout (10 s)".
