# SSH and SFTP client library for React Native

SSH and SFTP client library for React Native on iOS and Android.

[![Compile package](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/compile.yml/badge.svg)](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/compile.yml) [![Native build gates](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/native-build.yml/badge.svg)](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/native-build.yml) [![Release](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/release.yml/badge.svg)](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/actions/workflows/release.yml)

## Installation

```bash
npm install @speedshield/react-native-ssh-sftp
```

### iOS

No `Podfile` edits are needed. The iOS side is backed by [Citadel](https://github.com/orlandos-nl/Citadel), a pure-Swift SSH/SFTP library, vendored as a precompiled XCFramework and wired up through `RNSSHClient.podspec`, which CocoaPods and Expo's autolinking resolve automatically like any other autolinked native dependency.

Just run `pod install` in your `./ios` directory after installing the package, same as you would for any other native module:

```bash
cd ios
pod install
cd -
```

> [!TIP]
> Adding a `postinstall` script to your `package.json` file to run `pod install` after `npm install` is a good idea. The [`pod-install`](https://www.npmjs.com/package/pod-install) package is a good way to do this.
>
> ```json
> {
>   "scripts": {
>     "postinstall": "npx pod-install"
>   }
> }
> ```

> [!NOTE]
> This library requires **iOS 18.0 or later**, needed for the Swift concurrency APIs ([SE-0417](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md)) that the Citadel-based connection handling relies on. **tvOS is not supported.**

### Android

No additional steps are needed for Android.

### Linking

This library autolinks via the [Expo Modules API](https://docs.expo.dev/modules/overview/), so manual linking is not required in either setup:

- **Expo-managed apps** pick it up automatically.
- **Bare React Native apps** (RN >= 0.74) need the `expo` package installed as an optional dependency purely for its autolinking infrastructure - see [Installing Expo modules in an existing React Native project](https://docs.expo.dev/bare/installing-expo-modules/). You don't need any other part of the Expo SDK.

## Usage

All functions that run asynchronously where we have to wait for a result returns Promises that can reject if an error occurred.

> [!NOTE]
> On the old NMSSH-based iOS implementation, the Simulator only worked with the **x86_64** (Intel/Rosetta) Simulator, not the native **arm64** Simulator on Apple Silicon Macs - NMSSH didn't ship a universal Simulator slice, so you'd need to explicitly select or force an x86_64 Simulator target (see [this issue](https://github.com/SpeedshieldTechnologies/react-native-ssh-sftp/issues/20) for background). The Citadel-based rewrite's XCFramework does ship a genuine universal Simulator slice (`arm64` + `x86_64`, verified in its `Info.plist`), so this specific limitation shouldn't apply anymore - but that's link-level evidence, not a full functional test, so a physical device is still the safer choice until someone confirms a real SSH connection end-to-end on the Simulator.

### Create a client using password authentication

```javascript
import SSHClient from '@speedshield/react-native-ssh-sftp';

SSHClient.connectWithPassword(
  "10.0.0.10",
  22,
  "user",
  "password"
).then(client => {/*...*/});
```

### Create a client using public key authentication

```javascript
import SSHClient from '@speedshield/react-native-ssh-sftp';

SSHClient.connectWithKey(
  "10.0.0.10",
  22,
  "user",
  privateKey="-----BEGIN RSA...",
  passphrase
).then(client => {/*...*/});
```

#### Public key authentication is also supported

```plaintext
{privateKey: '-----BEGIN RSA......'}
{privateKey: '-----BEGIN RSA......', publicKey: 'ssh-rsa AAAAB3NzaC1yc2EA......'}
{privateKey: '-----BEGIN RSA......', publicKey: 'ssh-rsa AAAAB3NzaC1yc2EA......', passphrase: 'Password'}
```

### Close client

```javascript
client.disconnect();
```

### Execute SSH command

```javascript
const command = 'ls -l';
client.execute(command)
  .then(output => console.warn(output));
```

### Shell

#### Start shell

- Supported ptyType: vanilla, vt100, vt102, vt220, ansi, xterm

```javascript
const ptyType = 'vanilla';
client.startShell(ptyType)
  .then(() => {/*...*/});
```

#### Read from shell

```javascript
client.on('Shell', (event) => {
  if (event)
    console.warn(event);
});
```

#### Write to shell

```javascript
const str = 'ls -l\n';
client.writeToShell(str)
  .then(() => {/*...*/});
```

#### Close shell

```javascript
client.closeShell();
```

### SFTP

#### Connect SFTP

```javascript
client.connectSFTP()
  .then(() => {/*...*/});
```

#### List directory

```javascript
const path = '.';
client.sftpLs(path)
  .then(response => console.warn(response));
```

#### Create directory

```javascript
client.sftpMkdir('dirName')
  .then(() => {/*...*/});
```

#### Rename file or directory

```javascript
client.sftpRename('oldName', 'newName')
  .then(() => {/*...*/});
```

#### Remove directory

```javascript
client.sftpRmdir('dirName')
  .then(() => {/*...*/});
```

#### Remove file

```javascript
client.sftpRm('fileName')
  .then(() => {/*...*/});
```

#### Download file

```javascript
client.sftpDownload('[path-to-remote-file]', '[path-to-local-directory]')
  .then(downloadedFilePath => {
    console.warn(downloadedFilePath);
  });

// Download progress (setup before call)
client.on('DownloadProgress', (event) => {
  console.warn(event);
});

// Cancel download
client.sftpCancelDownload();
```

#### Upload file

```javascript
client.sftpUpload('[path-to-local-file]', '[path-to-remote-directory]')
  .then(() => {/*...*/});

// Upload progress (setup before call)
client.on('UploadProgress', (event) => {
  console.warn(event);
});

// Cancel upload
client.sftpCancelUpload();
```

#### Close SFTP

```javascript
client.disconnectSFTP();
```

## Example app

You can find a very simple example app for the usage of this library [here](https://github.com/dylankenneally/react-native-ssh-sftp-example) (predates the Expo Modules/Citadel rewrite, so treat it as a usage reference rather than a setup reference).

[longphung/rnssh-test-app](https://github.com/longphung/rnssh-test-app) is a minimal manual test harness kept up to date against this library's current architecture, including the `file:` sibling-directory setup this repo's own native code needs for local development.

## Credits

This package wraps the following libraries, which provide the actual SSH/SFTP functionality:

- [Citadel](https://github.com/orlandos-nl/Citadel) (MIT license) for iOS, by [Orlandos](https://github.com/orlandos-nl) - a pure-Swift SSH/SFTP library built on Apple's [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) (Apache License 2.0)
- [JSch](http://www.jcraft.com/jsch/) for Android ([from Matthias Wiedemann fork](https://github.com/mwiede/jsch))

This package is a fork of Emmanuel Natividad's [react-native-ssh-sftp](https://github.com/enatividad/react-native-ssh-sftp) package. The fork chain from there is as follows:

1. [Gabriel Paul "Cley Faye" Risterucci](https://github.com/KeeeX/react-native-ssh-sftp)
1. [Bishoy Mikhael](https://github.com/MrBmikhael/react-native-ssh-sftp)
1. [Qian Sha](https://github.com/shaqian/react-native-ssh-sftp)
