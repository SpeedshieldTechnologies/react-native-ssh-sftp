package com.speedshield.rnssh

import android.os.Bundle
import android.util.Log
import com.jcraft.jsch.Channel
import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.ChannelShell
import com.jcraft.jsch.ChannelSftp
import com.jcraft.jsch.JSch
import com.jcraft.jsch.KeyPair
import com.jcraft.jsch.Session
import com.jcraft.jsch.SftpProgressMonitor
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileWriter
import java.io.InputStreamReader
import java.util.Locale
import java.util.Properties
import java.util.concurrent.ConcurrentHashMap

private const val TAG = "RNSSHClient"

class KeyPairOrPasswordRecord : Record {
  @Field var privateKey: String = ""
  @Field var publicKey: String? = null
  @Field var passphrase: String? = null
}

class GeneratedKeyPairResult : Record {
  @Field var privateKey: String = ""
  @Field var publicKey: String = ""
}

class KeyDetailsResult : Record {
  @Field var keyType: String = ""
  @Field var keySize: Int = 0
}

class RNSSHClientModule : Module() {
  private class SSHClient {
    var session: Session? = null
    var bufferedReader: BufferedReader? = null
    var dataOutputStream: DataOutputStream? = null
    var channel: Channel? = null
    var sftpSession: ChannelSftp? = null
    var downloadContinue = false
    var uploadContinue = false
  }

  private val clientPool = ConcurrentHashMap<String, SSHClient>()

  private inner class ProgressMonitor(private val key: String, private val eventName: String) : SftpProgressMonitor {
    private var max = 0L
    private var count = 0L
    private var lastReportedPercent = 0L

    override fun init(op: Int, src: String?, dest: String?, max: Long) {
      this.max = max
    }

    override fun count(bytes: Long): Boolean {
      count += bytes
      val percent = if (max > 0) count * 100 / max else 0
      if (percent % 5 == 0L && percent > lastReportedPercent) {
        lastReportedPercent = percent
        sendEvent(
          eventName,
          Bundle().apply {
            putString("name", eventName)
            putString("key", key)
            putString("value", percent.toString())
          }
        )
      }
      val client = clientPool[key] ?: return false
      return if (eventName == "DownloadProgress") client.downloadContinue else client.uploadContinue
    }

    override fun end() {}
  }

  override fun definition() = ModuleDefinition {
    Name("RNSSHClient")

    Events("Shell", "DownloadProgress", "UploadProgress")

    AsyncFunction("connectToHostByPassword") { host: String, port: Int, username: String, password: String, key: String, promise: Promise ->
      connectToHost(host, port, username, password, null, key, promise)
    }

    AsyncFunction("connectToHostByKey") { host: String, port: Int, username: String, passwordOrKey: KeyPairOrPasswordRecord, key: String, promise: Promise ->
      connectToHost(host, port, username, null, passwordOrKey, key, promise)
    }

    AsyncFunction("execute") { command: String, key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        val channel = client.session!!.openChannel("exec") as ChannelExec
        channel.setCommand(command)
        channel.connect()

        val response = StringBuilder()
        BufferedReader(InputStreamReader(channel.inputStream)).useLines { lines ->
          lines.forEach { response.append(it).append("\r\n") }
        }
        promise.resolve(response.toString())
      } catch (e: Exception) {
        Log.e(TAG, "Error executing command: ${e.message}")
        promise.reject(TAG, e.message, e)
      }
    }

    AsyncFunction("startShell") { key: String, ptyType: String, promise: Promise ->
      Thread {
        try {
          val client = clientOrThrow(key)
          val channel = client.session!!.openChannel("shell") as ChannelShell
          channel.setPtyType(ptyType)
          channel.connect()

          client.channel = channel
          client.bufferedReader = BufferedReader(InputStreamReader(channel.inputStream))
          client.dataOutputStream = DataOutputStream(channel.outputStream)

          promise.resolve(null)

          while (true) {
            val line = client.bufferedReader?.readLine() ?: break
            sendEvent(
              "Shell",
              Bundle().apply {
                putString("name", "Shell")
                putString("key", key)
                putString("value", "$line\n")
              }
            )
          }
        } catch (e: Exception) {
          Log.e(TAG, "Error starting shell: ${e.message}")
          promise.reject(TAG, e.message, e)
        }
      }.start()
    }

    AsyncFunction("writeToShell") { str: String, key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        client.dataOutputStream!!.writeBytes(str)
        client.dataOutputStream!!.flush()
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Error writing to shell: ${e.message}")
        promise.reject(TAG, e.message, e)
      }
    }

    Function("closeShell") { key: String -> closeShellSync(key) }

    AsyncFunction("connectSFTP") { key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        val channelSftp = client.session!!.openChannel("sftp") as ChannelSftp
        channelSftp.connect()
        client.sftpSession = channelSftp
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Error connecting SFTP: ${e.message}")
        promise.reject(TAG, e.message, e)
      }
    }

    Function("disconnectSFTP") { key: String -> disconnectSftpSync(key) }

    AsyncFunction("sftpLs") { path: String, key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        val files = client.sftpSession!!.ls(path)
        val response = mutableListOf<String>()

        for (file in files) {
          var filename = file.filename
          if (filename.trim() == "." || filename.trim() == "..") continue

          var isDir = 0
          if (file.attrs.isDir) {
            isDir = 1
            filename += "/"
          }
          response.add(
            String.format(
              Locale.getDefault(),
              "{\"filename\":\"%s\"," +
                "\"isDirectory\":%d," +
                "\"modificationDate\":\"%s\"," +
                "\"lastAccess\":\"%s\"," +
                "\"fileSize\":%d," +
                "\"ownerUserID\":%d," +
                "\"ownerGroupID\":%d," +
                "\"permissions\":\"%s\"," +
                "\"flags\":%d}",
              filename,
              isDir,
              file.attrs.getMTime(),
              file.attrs.getATime(),
              file.attrs.getSize(),
              file.attrs.getUId(),
              file.attrs.getGId(),
              file.attrs.getPermissions(),
              file.attrs.getFlags()
            )
          )
        }
        promise.resolve(response)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to list path $path")
        promise.reject(TAG, "Failed to list path $path", e)
      }
    }

    AsyncFunction("sftpRename") { oldPath: String, newPath: String, key: String, promise: Promise ->
      try {
        clientOrThrow(key).sftpSession!!.rename(oldPath, newPath)
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to rename path $oldPath")
        promise.reject(TAG, "Failed to rename path $oldPath", e)
      }
    }

    AsyncFunction("sftpMkdir") { path: String, key: String, promise: Promise ->
      try {
        clientOrThrow(key).sftpSession!!.mkdir(path)
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to create directory $path")
        promise.reject(TAG, "Failed to create directory $path", e)
      }
    }

    AsyncFunction("sftpRm") { path: String, key: String, promise: Promise ->
      try {
        clientOrThrow(key).sftpSession!!.rm(path)
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to remove $path")
        promise.reject(TAG, "Failed to remove $path", e)
      }
    }

    AsyncFunction("sftpRmdir") { path: String, key: String, promise: Promise ->
      try {
        clientOrThrow(key).sftpSession!!.rmdir(path)
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to remove $path")
        promise.reject(TAG, "Failed to remove $path", e)
      }
    }

    AsyncFunction("sftpChmod") { path: String, permissions: Int, key: String, promise: Promise ->
      try {
        clientOrThrow(key).sftpSession!!.chmod(permissions, path)
        promise.resolve(null)
      } catch (e: Exception) {
        val msg = "Failed to chmod $path with permissions $permissions"
        Log.e(TAG, msg)
        promise.reject(TAG, msg, e)
      }
    }

    AsyncFunction("sftpDownload") { filePath: String, path: String, key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        client.downloadContinue = true
        client.sftpSession!!.get(filePath, path, ProgressMonitor(key, "DownloadProgress"))
        promise.resolve(path + "/" + File(filePath).name)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to download $filePath")
        promise.reject(TAG, "Failed to download $filePath", e)
      }
    }

    AsyncFunction("sftpUpload") { filePath: String, path: String, key: String, promise: Promise ->
      try {
        val client = clientOrThrow(key)
        client.uploadContinue = true
        client.sftpSession!!.put(
          filePath,
          path + "/" + File(filePath).name,
          ProgressMonitor(key, "UploadProgress"),
          ChannelSftp.OVERWRITE
        )
        promise.resolve(null)
      } catch (e: Exception) {
        Log.e(TAG, "Failed to upload $filePath")
        promise.reject(TAG, "Failed to upload $filePath", e)
      }
    }

    Function("sftpCancelDownload") { key: String ->
      clientPool[key]?.downloadContinue = false
    }

    Function("sftpCancelUpload") { key: String ->
      clientPool[key]?.uploadContinue = false
    }

    Function("disconnect") { key: String ->
      closeShellSync(key)
      disconnectSftpSync(key)
      clientPool[key]?.session?.disconnect()
    }

    AsyncFunction("generateKeyPair") { type: String, passphrase: String?, keySize: Int, comment: String, promise: Promise ->
      try {
        val jsch = JSch()
        val keyPair = KeyPair.genKeyPair(jsch, keyTypeFromString(type), keySize)

        val privateKeyOut = ByteArrayOutputStream()
        val publicKeyOut = ByteArrayOutputStream()
        val passphraseBytes = passphrase?.takeIf { it.isNotEmpty() }?.toByteArray()
        keyPair.writePrivateKey(privateKeyOut, passphraseBytes)
        keyPair.writePublicKey(publicKeyOut, comment)

        promise.resolve(
          GeneratedKeyPairResult().apply {
            privateKey = privateKeyOut.toString("UTF-8")
            publicKey = publicKeyOut.toString("UTF-8")
          }
        )

        privateKeyOut.close()
        publicKeyOut.close()
        keyPair.dispose()
      } catch (e: Exception) {
        Log.e(TAG, "Failed to generate key pair", e)
        promise.reject(TAG, "Failed to generate key pair: $e", e)
      }
    }

    AsyncFunction("getKeyDetails") { privateKey: String, promise: Promise ->
      var tempPrivateKeyFile: File? = null
      try {
        tempPrivateKeyFile = File.createTempFile("temp_private_key", ".pem").apply {
          deleteOnExit()
          FileWriter(this).use { it.write(privateKey) }
        }

        val jsch = JSch()
        val keyPair = KeyPair.load(jsch, tempPrivateKeyFile.absolutePath)

        val keyType = when (keyPair.keyType) {
          KeyPair.RSA -> "RSA"
          KeyPair.DSA -> "DSA"
          KeyPair.ECDSA -> "ECDSA"
          KeyPair.ED25519 -> "ED25519"
          else -> "UNKNOWN"
        }
        val keySize = keyPair.keySize
        keyPair.dispose()

        promise.resolve(
          KeyDetailsResult().apply {
            this.keyType = keyType
            this.keySize = keySize
          }
        )
      } catch (e: Exception) {
        promise.reject("Error", e.message, e)
      } finally {
        tempPrivateKeyFile?.delete()
      }
    }
  }

  private fun clientOrThrow(key: String): SSHClient =
    clientPool[key] ?: throw IllegalStateException("client is null")

  private fun closeShellSync(key: String) {
    val client = clientPool[key] ?: return
    try {
      client.channel?.disconnect()
      client.dataOutputStream?.apply { flush(); close() }
      client.bufferedReader?.close()
    } catch (e: Exception) {
      Log.e(TAG, "Error closing shell: ${e.message}")
    }
  }

  private fun disconnectSftpSync(key: String) {
    clientPool[key]?.sftpSession?.disconnect()
  }

  private fun keyTypeFromString(type: String): Int = when (type.lowercase()) {
    "dsa" -> KeyPair.DSA
    "rsa" -> KeyPair.RSA
    "ecdsa" -> KeyPair.ECDSA
    "ed25519" -> KeyPair.ED25519
    "ed448" -> KeyPair.ED448
    else -> throw IllegalArgumentException("Unsupported key type: $type")
  }

  private fun connectToHost(
    host: String,
    port: Int,
    username: String,
    password: String?,
    passwordOrKey: KeyPairOrPasswordRecord?,
    key: String,
    promise: Promise
  ) {
    Thread {
      try {
        val jsch = JSch()

        if (password == null && passwordOrKey != null) {
          jsch.addIdentity(
            "default",
            passwordOrKey.privateKey.toByteArray(),
            passwordOrKey.publicKey?.toByteArray(),
            passwordOrKey.passphrase?.toByteArray()
          )
        }

        val session = jsch.getSession(username, host, port)
        password?.let { session.setPassword(it) }

        session.setConfig(
          Properties().apply { setProperty("StrictHostKeyChecking", "no") }
        )
        session.connect()

        if (session.isConnected) {
          clientPool[key] = SSHClient().apply { this.session = session }
          Log.d(TAG, "Session connected")
          promise.resolve(null)
        }
      } catch (e: Exception) {
        Log.e(TAG, "Connection failed: ${e.message}")
        promise.reject(TAG, e.message, e)
      }
    }.start()
  }
}
