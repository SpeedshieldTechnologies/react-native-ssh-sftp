import ExpoModulesCore
import RNSSHClientDeps

struct KeyPairOrPasswordRecord: Record {
    @Field var privateKey: String = ""
    @Field var publicKey: String? = nil
    @Field var passphrase: String? = nil
}

struct GeneratedKeyPairResult: Record {
    @Field var privateKey: String = ""
    @Field var publicKey: String = ""
}

struct KeyDetailsResult: Record {
    @Field var keyType: String = ""
    @Field var keySize: Int = 0
}

public class RNSSHClientModule: Module {
    private let pool = RNSSHClientPool.shared

    public func definition() -> ModuleDefinition {
        Name("RNSSHClient")

        Events("Shell", "DownloadProgress", "UploadProgress")

        AsyncFunction("connectToHostByPassword") { (host: String, port: Int, username: String, password: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.connectWithPassword(key: key, host: host, port: port, username: username, password: password)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Connection to host \(host) failed: \(error)")
                }
            }
        }

        AsyncFunction("connectToHostByKey") { (host: String, port: Int, username: String, passwordOrKey: KeyPairOrPasswordRecord, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.connectWithKey(
                        key: key, host: host, port: port, username: username,
                        privateKey: passwordOrKey.privateKey, passphrase: passwordOrKey.passphrase
                    )
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Connection to host \(host) failed: \(error)")
                }
            }
        }

        AsyncFunction("execute") { (command: String, key: String, promise: Promise) in
            Task {
                do {
                    let response = try await self.pool.execute(key: key, command: command)
                    promise.resolve(response)
                } catch {
                    promise.reject("RNSSHClient", "Error executing command: \(error)")
                }
            }
        }

        AsyncFunction("startShell") { (key: String, ptyType: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.startShell(key: key, ptyType: ptyType) { [weak self] output in
                        self?.sendEvent("Shell", ["name": "Shell", "key": key, "value": output])
                    }
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Error starting shell: \(error)")
                }
            }
        }

        AsyncFunction("writeToShell") { (str: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.writeToShell(key: key, text: str)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Error writing to shell: \(error)")
                }
            }
        }

        Function("closeShell") { (key: String) in
            Task { await self.pool.closeShell(key: key) }
        }

        AsyncFunction("connectSFTP") { (key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.connectSFTP(key: key)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Error connecting SFTP: \(error)")
                }
            }
        }

        Function("disconnectSFTP") { (key: String) in
            Task { await self.pool.disconnectSFTP(key: key) }
        }

        AsyncFunction("sftpLs") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    let response = try await self.pool.sftpList(key: key, path: path)
                    promise.resolve(response)
                } catch {
                    promise.reject("RNSSHClient", "Failed to list path \(path): \(error)")
                }
            }
        }

        AsyncFunction("sftpRename") { (oldPath: String, newPath: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRename(key: key, oldPath: oldPath, newPath: newPath)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to rename path \(oldPath): \(error)")
                }
            }
        }

        AsyncFunction("sftpMkdir") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpMkdir(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to create directory \(path): \(error)")
                }
            }
        }

        AsyncFunction("sftpRm") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRm(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to remove \(path): \(error)")
                }
            }
        }

        AsyncFunction("sftpRmdir") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRmdir(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to remove \(path): \(error)")
                }
            }
        }

        AsyncFunction("sftpChmod") { (path: String, permissions: Int, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpChmod(key: key, path: path, permissions: permissions)
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to chmod \(path) with permissions \(permissions): \(error)")
                }
            }
        }

        AsyncFunction("sftpDownload") { (filePath: String, path: String, key: String, promise: Promise) in
            Task {
                do {
                    let localPath = try await self.pool.sftpDownload(key: key, remotePath: filePath, localDirectory: path) { [weak self] percent in
                        self?.sendEvent("DownloadProgress", ["name": "DownloadProgress", "key": key, "value": String(percent)])
                    }
                    promise.resolve(localPath)
                } catch {
                    promise.reject("RNSSHClient", "Failed to download \(filePath): \(error)")
                }
            }
        }

        AsyncFunction("sftpUpload") { (filePath: String, path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpUpload(key: key, localPath: filePath, remoteDirectory: path) { [weak self] percent in
                        self?.sendEvent("UploadProgress", ["name": "UploadProgress", "key": key, "value": String(percent)])
                    }
                    promise.resolve(nil)
                } catch {
                    promise.reject("RNSSHClient", "Failed to upload \(filePath): \(error)")
                }
            }
        }

        Function("sftpCancelDownload") { (key: String) in
            Task { await self.pool.sftpCancelDownload(key: key) }
        }

        Function("sftpCancelUpload") { (key: String) in
            Task { await self.pool.sftpCancelUpload(key: key) }
        }

        Function("disconnect") { (key: String) in
            Task { await self.pool.disconnect(key: key) }
        }

        AsyncFunction("generateKeyPair") { (type: String, passphrase: String?, keySize: Int, comment: String, promise: Promise) in
            Task {
                do {
                    let pair = try await self.pool.generateKeyPair(type: type, passphrase: passphrase, keySize: keySize, comment: comment)
                    promise.resolve(GeneratedKeyPairResult(privateKey: pair.privateKey, publicKey: pair.publicKey))
                } catch {
                    promise.reject("RNSSHClient", "Failed to generate key pair: \(error)")
                }
            }
        }

        AsyncFunction("getKeyDetails") { (privateKey: String, promise: Promise) in
            Task {
                do {
                    let details = try self.pool.getKeyDetails(privateKey: privateKey)
                    promise.resolve(KeyDetailsResult(keyType: details.keyType, keySize: details.keySize))
                } catch {
                    promise.reject("RNSSHClient", "Error: \(error)")
                }
            }
        }
    }
}
