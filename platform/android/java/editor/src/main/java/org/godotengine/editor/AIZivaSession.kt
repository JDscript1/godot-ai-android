package org.godotengine.editor

import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException

/** Kernel-held ownership: a saved JSON status can never keep a dead session alive. */
class AIZivaSession(private val directory: File) {
    class Lease(private val file: RandomAccessFile, private val lock: FileLock, private val key: String) : AutoCloseable {
        override fun close() = synchronized(held) {
            try { if (lock.isValid) lock.release() } finally { file.close(); held.remove(key) }
        }
    }
    fun acquire(): Lease? = synchronized(held) {
        val key = directory.canonicalPath
        if (key in held) return null
        check(directory.isDirectory || directory.mkdirs())
        val target = File(directory, "session.lock")
        check(!Files.isSymbolicLink(directory.toPath()) && !Files.isSymbolicLink(target.toPath()))
        val file = RandomAccessFile(target, "rw")
        return try {
            val lock = try { file.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
            if (lock == null) { file.close(); null } else { held.add(key); Lease(file, lock, key) }
        } catch (error: Exception) { file.close(); throw error }
    }
    fun active(): Boolean {
        val lease = acquire() ?: return true
        lease.close()
        return false
    }
    companion object {
        private val held = HashSet<String>()
        fun ownedPorts(share: File, pid: Int): List<Int> = share.walkTopDown().maxDepth(10).filter {
            it.isFile && !Files.isSymbolicLink(it.toPath()) && it.name.startsWith("sidecar-$pid-") && it.name.endsWith(".port") && it.length() < 16
        }.mapNotNull { it.readText().trim().toIntOrNull()?.takeIf { port -> port in 1024..65535 } }.distinct().toList()
        fun bootId(): String = try { File("/proc/sys/kernel/random/boot_id").readText().trim() } catch (_: Exception) { "" }
        fun processStart(pid: Int): String = try {
            File("/proc/$pid/stat").readText().substringAfterLast(") ").split(' ')[19]
        } catch (_: Exception) { "" }
    }
}
