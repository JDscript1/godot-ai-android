package org.godotengine.editor

import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.nio.file.Files
import java.util.UUID
import java.util.zip.ZipFile

/** Optional upstream download. No Ziva binaries or proprietary UI are redistributed in the APK. */
class AIZivaPackage(private val root: File, private val spec: Release = RELEASE) {
    data class Release(val version: String, val url: String, val archiveSize: Long, val archiveHash: String,
        val member: String, val binarySize: Long, val binaryHash: String)
    companion object {
        val RELEASE = Release("v3.3.2",
            "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/v3.3.2/ziva-ai-agent-v3.3.2-godot-v4.2.0-linux-arm64.zip",
            217601938, "0a852ea62028d6fa1dce10693b20a66ce208b338b778eaecf09ee55e00fd5d66",
            "addons/ziva_agent/zivacode/linux_arm64/zivacode", 116771624,
            "7797be07153d515fb0a96a8438f811d633610e4e39caa582334e87cc5ef6c200")
        const val BASE_URL = "http://127.0.0.1:7012/"
    }
    private val directory get() = safe("opt/godot-tools/ziva/${spec.version}")
    val binary get() = File(directory, "zivacode")
    val guestBinary get() = "/opt/godot-tools/ziva/${spec.version}/zivacode"

    private fun safe(path: String): File {
        require(spec.version.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+")))
        check(root.isDirectory && !Files.isSymbolicLink(root.toPath())) { "Linux indisponibil." }
        var file = root
        for (part in path.split('/')) {
            require(part.isNotEmpty() && part != "." && part != "..")
            file = File(file, part)
            check(!Files.isSymbolicLink(file.toPath())) { "Cale Ziva nesigură." }
        }
        check(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
        return file
    }

    fun installed(): Boolean = try { binary.isFile && binary.length() == spec.binarySize } catch (_: Exception) { false }
    fun verify() {
        check(installed() && AILinuxRuntimeFiles.sha(binary) == spec.binaryHash) { "Pachet Ziva absent sau corupt. Reinstalează Ziva." }
    }

    fun install(cache: File, cancelled: () -> Boolean, progress: (String) -> Unit) {
        check(cache.isDirectory || cache.mkdirs())
        check(root.usableSpace >= spec.archiveSize + spec.binarySize + 32L * 1024 * 1024) { "Sunt necesari aproximativ 370 MB liberi pentru instalarea Ziva." }
        val archive = File(cache, "ziva-${UUID.randomUUID()}.zip")
        try {
            progress("Descarc Ziva de la furnizor…")
            download(archive, cancelled, progress)
            progress("Verific pachetul Ziva…")
            extract(archive, cancelled)
        } finally { archive.delete() }
    }

    private fun download(destination: File, cancelled: () -> Boolean, progress: (String) -> Unit) {
        var location = URI(spec.url)
        repeat(6) { redirect ->
            check(!cancelled()) { "Operație anulată." }
            require(location.scheme == "https" && location.userInfo == null)
            val connection = location.toURL().openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15000; connection.readTimeout = 15000
            connection.setRequestProperty("User-Agent", "Godot-AI-Ziva-Installer")
            try {
                if (connection.responseCode in listOf(301, 302, 303, 307, 308)) {
                    check(redirect < 5) { "Prea multe redirecționări la descărcare." }
                    location = location.resolve(connection.getHeaderField("Location") ?: error("Redirecționare invalidă."))
                    return@repeat
                }
                check(connection.responseCode == 200) { "Descărcarea Ziva a eșuat (HTTP ${connection.responseCode})." }
                val expectedLength = connection.contentLengthLong
                check(expectedLength == -1L || expectedLength == spec.archiveSize) { "Dimensiune Ziva neașteptată." }
                connection.inputStream.use { input -> destination.outputStream().use { output ->
                    val buffer = ByteArray(65536); var count = 0L; var last = -1L
                    while (true) {
                        check(!cancelled()) { "Operație anulată." }
                        val size = input.read(buffer); if (size < 0) break
                        count += size; check(count <= spec.archiveSize) { "Pachet Ziva prea mare." }
                        output.write(buffer, 0, size)
                        val megabytes = count / (1024 * 1024)
                        if (megabytes / 8 != last / 8) { last = megabytes; progress("Descarc Ziva: $megabytes / 208 MB") }
                    }
                    check(count == spec.archiveSize) { "Descărcarea Ziva este incompletă." }
                } }
                return
            } finally { connection.disconnect() }
        }
        error("Descărcarea Ziva nu s-a finalizat.")
    }

    /** Extract only fixed members; archive paths are never used as destination paths. */
    fun extract(archive: File, cancelled: () -> Boolean = { false }) {
        check(archive.length() == spec.archiveSize && AILinuxRuntimeFiles.sha(archive) == spec.archiveHash) { "Verificarea SHA-256 Ziva a eșuat." }
        val target = directory
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        val staging = File(target.parentFile, "staging-${UUID.randomUUID()}")
        check(staging.mkdir())
        try {
            ZipFile(archive).use { zip ->
                val names = setOf(spec.member, "addons/ziva_agent/LICENSE.md")
                val members = zip.entries().asSequence().filter { it.name in names }.toList()
                check(members.map { it.name }.toSet() == names && members.size == names.size) { "Structură Ziva invalidă." }
                for (member in members) {
                    val limit = if (member.name == spec.member) spec.binarySize else 65536L
                    check(!member.isDirectory && member.size in 1..limit)
                    if (member.name == spec.member) check(member.size == spec.binarySize)
                    val file = File(staging, if (member.name == spec.member) "zivacode" else "LICENSE.md")
                    zip.getInputStream(member).use { input -> file.outputStream().use { output ->
                        val buffer = ByteArray(65536); var count = 0L
                        while (true) {
                            check(!cancelled()) { "Operație anulată." }
                            val size = input.read(buffer); if (size < 0) break
                            count += size; check(count <= limit); output.write(buffer, 0, size)
                        }
                        check(count == member.size) { "Fișier Ziva incomplet." }
                    } }
                }
            }
            val executable = File(staging, "zivacode")
            check(AILinuxRuntimeFiles.sha(executable) == spec.binaryHash) { "Executabil Ziva corupt." }
            check(executable.setExecutable(true, true))
            check(!cancelled()) { "Operație anulată." }
            // Retain the previous executable until the replacement has passed all checks.
            val previous = File(target.parentFile, "previous-${UUID.randomUUID()}")
            val hadPrevious = target.exists()
            if (hadPrevious) check(target.renameTo(previous)) { "Instalarea Ziva existentă nu a putut fi păstrată." }
            if (!staging.renameTo(target)) {
                if (hadPrevious) check(previous.renameTo(target)) { "Instalarea Ziva trebuie reparată." }
                error("Pachetul Ziva nu a putut fi activat.")
            }
            if (hadPrevious) AILinuxRuntimeFiles.deleteTree(previous)
        } finally { AILinuxRuntimeFiles.deleteTree(staging) }
    }
}
