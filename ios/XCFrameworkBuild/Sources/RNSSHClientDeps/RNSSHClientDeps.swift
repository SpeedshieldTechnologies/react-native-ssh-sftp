import Foundation
internal import Citadel
internal import NIOCore
internal import NIOSSH
internal import NIOTransportServices
internal import Crypto

public enum RNSSHClientDepsError: Error, CustomStringConvertible {
    case clientNotFound
    case sftpNotConnected
    case shellNotStarted
    case unsupportedKeyType(String)
    case unsupportedKeyGenerationType(String)

    public var description: String {
        switch self {
        case .clientNotFound: return "client is null"
        case .sftpNotConnected: return "SFTP is not connected"
        case .shellNotStarted: return "Shell is not started"
        case .unsupportedKeyType(let type): return "Unsupported key type: \(type)"
        case .unsupportedKeyGenerationType(let type):
            return "Key generation is not yet supported for type: \(type) (only ed25519 is currently supported on iOS)"
        }
    }
}

public struct RNSSHKeyPair: Sendable {
    public let privateKey: String
    public let publicKey: String
}

public struct RNSSHKeyDetails: Sendable {
    public let keyType: String
    public let keySize: Int
}

/// Owns every live SSH/SFTP/shell session for this native module, addressed by the same
/// per-instance `key` string the JS side already generates. An actor gives us the same
/// serialization guarantee the old Obj-C code got from its single serial dispatch queue.
public actor RNSSHClientPool {
    public static let shared = RNSSHClientPool()

    private final class ClientState {
        var client: SSHClient?
        var sftp: SFTPClient?
        var shellWriter: TTYStdinWriter?
        var shellShouldStop = false
        var downloadContinue = true
        var uploadContinue = true
    }

    // Network.framework-backed event loop group: this is the actual fix for the Wi-Fi/cellular
    // bug. Deliberate, explicit construction - never fall back to the default POSIX-socket group.
    private let eventLoopGroup = NIOTSEventLoopGroup()
    private var clients: [String: ClientState] = [:]

    public init() {}

    private func state(for key: String) throws -> ClientState {
        guard let state = clients[key] else { throw RNSSHClientDepsError.clientNotFound }
        return state
    }

    // MARK: - Connect

    public func connectWithPassword(key: String, host: String, port: Int, username: String, password: String) async throws {
        try await connect(key: key, host: host, port: port, authMethod: .passwordBased(username: username, password: password))
    }

    public func connectWithKey(key: String, host: String, port: Int, username: String, privateKey: String, passphrase: String?) async throws {
        let authMethod = try Self.authMethod(username: username, privateKey: privateKey, passphrase: passphrase)
        try await connect(key: key, host: host, port: port, authMethod: authMethod)
    }

    private func connect(key: String, host: String, port: Int, authMethod: SSHAuthenticationMethod) async throws {
        var settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { authMethod },
            hostKeyValidator: .acceptAnything()
        )
        settings.group = eventLoopGroup

        let client = try await SSHClient.connect(to: settings)
        let state = ClientState()
        state.client = client
        clients[key] = state
    }

    private static func authMethod(username: String, privateKey: String, passphrase: String?) throws -> SSHAuthenticationMethod {
        let passphraseData = passphrase?.isEmpty == false ? passphrase.map { Data($0.utf8) } : nil
        let keyType = try SSHKeyDetection.detectPrivateKeyType(from: privateKey)

        switch keyType {
        case .rsa:
            let key = try Insecure.RSA.PrivateKey(sshRsa: privateKey, decryptionKey: passphraseData)
            return .rsa(username: username, privateKey: key)
        case .ed25519:
            let key = try Curve25519.Signing.PrivateKey(sshEd25519: privateKey, decryptionKey: passphraseData)
            return .ed25519(username: username, privateKey: key)
        default:
            throw RNSSHClientDepsError.unsupportedKeyType(keyType.description)
        }
    }

    // MARK: - Execute

    /// Matches the existing cross-platform contract: resolves with whatever stdout was captured,
    /// even on a non-zero exit code (Citadel's own `executeCommand` convenience discards output
    /// entirely on a non-zero exit, which would be a real behavior change from today).
    public func execute(key: String, command: String) async throws -> String {
        guard let client = try state(for: key).client else { throw RNSSHClientDepsError.clientNotFound }

        var output = ByteBuffer()
        do {
            let stream = try await client.executeCommandStream(command)
            for try await chunk in stream {
                if case .stdout(let buffer) = chunk {
                    output.writeImmutableBuffer(buffer)
                }
            }
        } catch is SSHClient.CommandFailed {
            // Preserve existing behavior: a non-zero exit still resolves with captured output.
        }
        return String(buffer: output)
    }

    // MARK: - Shell

    public func startShell(key: String, ptyType: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        let clientState = try state(for: key)
        guard let client = clientState.client else { throw RNSSHClientDepsError.clientNotFound }
        clientState.shellShouldStop = false

        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: ptyType,
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        let resumeGuard = ResumeOnceGuard()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    try await client.withPTY(request) { inbound, outbound in
                        await self.setShellWriter(key: key, writer: outbound)
                        resumeGuard.resumeOnce { continuation.resume() }

                        // `inbound` isn't cancellation-aware on its own (it just waits for the
                        // next value indefinitely), so closeShell() can't interrupt a suspended
                        // read directly. Race it against a poll of the stop flag instead - this
                        // is the standard bridge for wrapping a non-cancellable async sequence.
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                do {
                                    for try await output in inbound {
                                        if await self.shouldStopShell(key: key) { break }
                                        switch output {
                                        case .stdout(let buffer), .stderr(let buffer):
                                            onOutput(String(buffer: buffer) + "\n")
                                        }
                                    }
                                } catch {
                                    // Stream ended with an error (e.g. remote closed); nothing further to relay.
                                }
                            }
                            group.addTask {
                                while await !self.shouldStopShell(key: key) {
                                    try? await Task.sleep(nanoseconds: 200_000_000)
                                }
                            }
                            await group.next()
                            group.cancelAll()
                        }
                    }
                } catch {
                    resumeGuard.resumeOnce { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private func setShellWriter(key: String, writer: TTYStdinWriter) {
        clients[key]?.shellWriter = writer
    }

    private func shouldStopShell(key: String) -> Bool {
        clients[key]?.shellShouldStop ?? true
    }

    public func writeToShell(key: String, text: String) async throws {
        guard let writer = try state(for: key).shellWriter else { throw RNSSHClientDepsError.shellNotStarted }
        try await writer.write(ByteBuffer(string: text))
    }

    /// Signals the shell's read loop to stop within ~200ms (see startShell) and drops the
    /// writer so further writeToShell calls fail immediately rather than silently no-op.
    public func closeShell(key: String) {
        clients[key]?.shellShouldStop = true
        clients[key]?.shellWriter = nil
    }

    // MARK: - SFTP

    public func connectSFTP(key: String) async throws {
        let clientState = try state(for: key)
        guard let client = clientState.client else { throw RNSSHClientDepsError.clientNotFound }
        clientState.sftp = try await client.openSFTP()
    }

    public func disconnectSFTP(key: String) {
        guard let sftp = clients[key]?.sftp else { return }
        clients[key]?.sftp = nil
        Task { try? await sftp.close() }
    }

    /// Hand-rolled JSON strings, matching Android's sftpLs format exactly (kept in sync per
    /// this repo's own CLAUDE.md) - the TS side strips control characters and JSON.parses each entry.
    public func sftpList(key: String, path: String) async throws -> [String] {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }

        let entries = try await sftp.listDirectory(atPath: path).flatMap(\.components)
        var response: [String] = []

        for entry in entries {
            let filename = entry.filename
            if filename == "." || filename == ".." { continue }

            let isDirectory = (entry.attributes.permissions.map { $0 & 0o170000 == 0o040000 } ?? false)
            let displayName = isDirectory ? filename + "/" : filename
            let modificationDate = Int(entry.attributes.accessModificationTime?.modificationTime.timeIntervalSince1970 ?? 0)
            let lastAccess = Int(entry.attributes.accessModificationTime?.accessTime.timeIntervalSince1970 ?? 0)

            response.append(
                "{\"filename\":\"\(displayName.escapedForJSON)\","
                + "\"isDirectory\":\(isDirectory ? 1 : 0),"
                + "\"modificationDate\":\"\(modificationDate)\","
                + "\"lastAccess\":\"\(lastAccess)\","
                + "\"fileSize\":\(entry.attributes.size ?? 0),"
                + "\"ownerUserID\":\(entry.attributes.uidgid?.userId ?? 0),"
                + "\"ownerGroupID\":\(entry.attributes.uidgid?.groupId ?? 0),"
                + "\"permissions\":\"\(entry.attributes.permissions ?? 0)\","
                + "\"flags\":\(entry.attributes.flags.rawValue)}"
            )
        }

        return response
    }

    public func sftpRename(key: String, oldPath: String, newPath: String) async throws {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }
        try await sftp.rename(at: oldPath, to: newPath)
    }

    public func sftpMkdir(key: String, path: String) async throws {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }
        try await sftp.createDirectory(atPath: path)
    }

    public func sftpRm(key: String, path: String) async throws {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }
        try await sftp.remove(at: path)
    }

    public func sftpRmdir(key: String, path: String) async throws {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }
        try await sftp.rmdir(at: path)
    }

    public func sftpChmod(key: String, path: String, permissions: Int) async throws {
        guard let sftp = try state(for: key).sftp else { throw RNSSHClientDepsError.sftpNotConnected }
        var attributes = SFTPFileAttributes()
        attributes.permissions = UInt32(permissions)
        try await sftp.setAttributes(at: path, to: attributes)
    }

    private static let transferChunkSize: UInt32 = 32_000

    public func sftpDownload(
        key: String,
        remotePath: String,
        localDirectory: String,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws -> String {
        let clientState = try state(for: key)
        guard let sftp = clientState.sftp else { throw RNSSHClientDepsError.sftpNotConnected }

        clientState.downloadContinue = true
        let fileName = (remotePath as NSString).lastPathComponent
        let localPath = (localDirectory as NSString).appendingPathComponent(fileName)

        try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            let totalSize = try await file.readAttributes().size ?? 0
            var offset: UInt64 = 0
            var lastReportedPercent = -1

            FileManager.default.createFile(atPath: localPath, contents: nil)
            let output = FileHandle(forWritingAtPath: localPath)

            while clientState.downloadContinue {
                let chunk = try await file.read(from: offset, length: Self.transferChunkSize)
                if chunk.readableBytes == 0 { break }

                output?.write(Data(chunk.readableBytesView))
                offset += UInt64(chunk.readableBytes)

                if totalSize > 0 {
                    let percent = Int(offset * 100 / totalSize)
                    if percent % 5 == 0 && percent > lastReportedPercent {
                        lastReportedPercent = percent
                        onProgress(percent)
                    }
                }
            }

            try output?.close()
        }

        return localPath
    }

    public func sftpUpload(
        key: String,
        localPath: String,
        remoteDirectory: String,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws {
        let clientState = try state(for: key)
        guard let sftp = clientState.sftp else { throw RNSSHClientDepsError.sftpNotConnected }

        clientState.uploadContinue = true
        let fileName = (localPath as NSString).lastPathComponent
        let remotePath = remoteDirectory + "/" + fileName

        guard let input = FileHandle(forReadingAtPath: localPath) else {
            throw RNSSHClientDepsError.clientNotFound
        }
        defer { try? input.close() }

        let totalSize = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? UInt64) ?? 0

        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            var offset: UInt64 = 0
            var lastReportedPercent = -1

            while clientState.uploadContinue {
                let chunkData = input.readData(ofLength: Int(Self.transferChunkSize))
                if chunkData.isEmpty { break }

                try await file.write(ByteBuffer(bytes: chunkData), at: offset)
                offset += UInt64(chunkData.count)

                if totalSize > 0 {
                    let percent = Int(offset * 100 / totalSize)
                    if percent % 5 == 0 && percent > lastReportedPercent {
                        lastReportedPercent = percent
                        onProgress(percent)
                    }
                }
            }
        }
    }

    public func sftpCancelDownload(key: String) {
        clients[key]?.downloadContinue = false
    }

    public func sftpCancelUpload(key: String) {
        clients[key]?.uploadContinue = false
    }

    // MARK: - Disconnect

    public func disconnect(key: String) async {
        closeShell(key: key)
        disconnectSFTP(key: key)
        if let client = clients[key]?.client {
            try? await client.close()
        }
        clients[key] = nil
    }

    // MARK: - Keys

    /// Only Ed25519 is currently supported: Citadel's public API doesn't expose an
    /// OpenSSH-format export for generated RSA/ECDSA keys (only for parsing existing ones).
    public func generateKeyPair(type: String, passphrase: String?, comment: String) throws -> RNSSHKeyPair {
        guard type.lowercased() == "ed25519" else {
            throw RNSSHClientDepsError.unsupportedKeyGenerationType(type)
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let privateKeyString = privateKey.makeSSHRepresentation(comment: comment)

        // Proper SSH wire-format encoding (length-prefixed type + key blob), not just the raw
        // key bytes base64'd - that would produce a string no real SSH tooling could parse.
        let nioPublicKey = NIOSSHPrivateKey(ed25519Key: privateKey).publicKey
        let publicKeyString = String(openSSHPublicKey: nioPublicKey) + " " + comment

        return RNSSHKeyPair(privateKey: privateKeyString, publicKey: publicKeyString)
    }

    /// Note: RSA key size can't be determined here - Citadel's `Insecure.RSA.PrivateKey` doesn't
    /// expose its modulus bit length publicly, only the fixed-size EC/Ed25519 curve sizes are known
    /// ahead of time. Returns 0 for RSA rather than a fabricated value.
    public nonisolated func getKeyDetails(privateKey: String) throws -> RNSSHKeyDetails {
        let keyType = try SSHKeyDetection.detectPrivateKeyType(from: privateKey)
        let keySize: Int
        switch keyType {
        case .rsa: keySize = 0
        case .ed25519: keySize = 256
        case .ecdsaP256: keySize = 256
        case .ecdsaP384: keySize = 384
        case .ecdsaP521: keySize = 521
        default: keySize = 0
        }
        return RNSSHKeyDetails(keyType: keyType.description, keySize: keySize)
    }
}

/// Guards a `CheckedContinuation` against being resumed twice - `startShell` can have its
/// continuation resumed from either the successful-connect path or the outer error path,
/// and only one of those may ever actually fire.
private final class ResumeOnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        body()
    }
}

private extension String {
    var escapedForJSON: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
