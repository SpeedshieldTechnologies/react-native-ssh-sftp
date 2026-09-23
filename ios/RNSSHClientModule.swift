import ExpoModulesCore
import RNSSHClientDeps

/// `Exception`'s own `reason` is a computed property hard-coded to "undefined reason" in the
/// base class - the `Exception(name:description:code:)` convenience initializer sets
/// `description`, not `reason`, but JS-side error messages read `reason`. So every rejection
/// via that convenience initializer silently loses its message text. Overriding `reason`
/// directly is the only way to actually get a message through to JS.
final class RNSSHClientException: Exception {
    private let customReason: String

    init(_ reason: String) {
        self.customReason = reason
        super.init()
        self.name = "RNSSHClient"
    }

    override var reason: String { customReason }
}

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
                    promise.reject(RNSSHClientException("Connection to host \(host) failed: \(error)"))
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
                    promise.reject(RNSSHClientException("Connection to host \(host) failed: \(error)"))
                }
            }
        }

        AsyncFunction("execute") { (command: String, key: String, promise: Promise) in
            Task {
                do {
                    let response = try await self.pool.execute(key: key, command: command)
                    promise.resolve(response)
                } catch {
                    promise.reject(RNSSHClientException("Error executing command: \(error)"))
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
                    promise.reject(RNSSHClientException("Error starting shell: \(error)"))
                }
            }
        }

        AsyncFunction("writeToShell") { (str: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.writeToShell(key: key, text: str)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Error writing to shell: \(error)"))
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
                    promise.reject(RNSSHClientException("Error connecting SFTP: \(error)"))
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
                    promise.reject(RNSSHClientException("Failed to list path \(path): \(error)"))
                }
            }
        }

        AsyncFunction("sftpRename") { (oldPath: String, newPath: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRename(key: key, oldPath: oldPath, newPath: newPath)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Failed to rename path \(oldPath): \(error)"))
                }
            }
        }

        AsyncFunction("sftpMkdir") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpMkdir(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Failed to create directory \(path): \(error)"))
                }
            }
        }

        AsyncFunction("sftpRm") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRm(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Failed to remove \(path): \(error)"))
                }
            }
        }

        AsyncFunction("sftpRmdir") { (path: String, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpRmdir(key: key, path: path)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Failed to remove \(path): \(error)"))
                }
            }
        }

        AsyncFunction("sftpChmod") { (path: String, permissions: Int, key: String, promise: Promise) in
            Task {
                do {
                    try await self.pool.sftpChmod(key: key, path: path, permissions: permissions)
                    promise.resolve(nil)
                } catch {
                    promise.reject(RNSSHClientException("Failed to chmod \(path) with permissions \(permissions): \(error)"))
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
                    promise.reject(RNSSHClientException("Failed to download \(filePath): \(error)"))
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
                    promise.reject(RNSSHClientException("Failed to upload \(filePath): \(error)"))
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
                    promise.reject(RNSSHClientException("Failed to generate key pair: \(error)"))
                }
            }
        }

        AsyncFunction("getKeyDetails") { (privateKey: String, promise: Promise) in
            Task {
                do {
                    let details = try self.pool.getKeyDetails(privateKey: privateKey)
                    promise.resolve(KeyDetailsResult(keyType: details.keyType, keySize: details.keySize))
                } catch {
                    promise.reject(RNSSHClientException("Error: \(error)"))
                }
            }
        }
    }
}
