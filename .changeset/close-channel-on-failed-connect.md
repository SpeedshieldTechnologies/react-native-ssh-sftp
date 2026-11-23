---
"@speedshield/react-native-ssh-sftp": patch
---

iOS: close the TCP connection when the SSH handshake or login fails. Citadel left it open, so each failed connect held an unauthenticated session on the server until its auth timeout, and after a few failures the server dropped every new login from that device ("Connect timeout (10 s)").
