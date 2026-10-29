package org.godotengine.editor

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.util.UUID
import java.util.zip.ZipFile

/** Optional upstream download. No Ziva binaries or proprietary UI are redistributed in the APK. */
class AIZivaPackage(private val root: File, private var spec: Release = activeRelease(root)) {
    data class Release(val version: String, val url: String, val archiveSize: Long, val archiveHash: String,
        val member: String, val binarySize: Long, val binaryHash: String) {
        fun json() = JSONObject().put("version", version).put("url", url).put("archive_size", archiveSize)
            .put("archive_hash", archiveHash).put("member", member).put("binary_size", binarySize).put("binary_hash", binaryHash)
    }
    companion object {
        private const val ADDON = "addons/ziva_agent"
        private const val PREFIX = "$ADDON/"
        private const val MAX_FILE = 320L * 1024 * 1024
        private const val UNPACKED_LIMIT = 600L * 1024 * 1024
        private const val MAX_FILES = 4000
        val RELEASE = Release("v3.3.2",
            "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/v3.3.2/ziva-ai-agent-v3.3.2-godot-v4.2.0-linux-arm64.zip",
            217601938, "0a852ea62028d6fa1dce10693b20a66ce208b338b778eaecf09ee55e00fd5d66",
            "$ADDON/zivacode/linux_arm64/zivacode", 116771624,
            "7797be07153d515fb0a96a8438f811d633610e4e39caa582334e87cc5ef6c200")
        fun fromJson(json: JSONObject): Release {
            val version = json.getString("version")
            require(version.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+"))) { "Versiune Ziva invalidă." }
            val expected = "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/$version/ziva-ai-agent-$version-godot-v4.2.0-linux-arm64.zip"
            require(json.getString("url") == expected) { "Sursă Ziva neoficială sau arhitectură incompatibilă." }
            val hash = json.getString("archive_hash")
            val size = json.getLong("archive_size")
            require(hash.matches(Regex("[a-f0-9]{64}")) && size in 1..(512L * 1024 * 1024)) { "Integritate Ziva absentă." }
            val member = "$ADDON/zivacode/linux_arm64/zivacode"
            require(json.optString("member", member) == member)
            val binarySize = json.optLong("binary_size", 0)
            val binaryHash = json.optString("binary_hash")
            require((binarySize == 0L && binaryHash.isEmpty()) ||
                (binarySize in 1..MAX_FILE && binaryHash.matches(Regex("[a-f0-9]{64}"))))
            return Release(version, expected, size, hash, member, binarySize, binaryHash)
        }
        fun activeRelease(root: File): Release {
            val file = File(root, "opt/godot-tools/ziva/active.json")
            if (!file.isFile) return RELEASE
            check(!Files.isSymbolicLink(file.toPath()))
            return fromJson(AILinuxRuntimeFiles.readJson(file)).also { require(it.binarySize > 0) }
        }

    }
    val version get() = spec.version
    val extension get() = "/opt/godot-tools/ziva/$version/$ADDON/bin/linux_arm64/libziva_agent.linux.release.arm64.so"
    fun activate() { verify(); AILinuxRuntimeFiles.writeJson(safe("opt/godot-tools/ziva/active.json"), spec.json()) }
    private val directory get() = safe("opt/godot-tools/ziva/${spec.version}")
    val addon get() = File(directory, ADDON)
    val binary get() = File(directory, spec.member)
    val guestBinary get() = "/opt/godot-tools/ziva/${spec.version}/${spec.member}"

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

    fun installed(): Boolean = try {
        addon.isDirectory && File(addon, "ziva_agent.gdextension").isFile && File(addon, "manifest.json").isFile &&
            binary.isFile && binary.length() == effective().binarySize
    } catch (_: Exception) { false }

    private fun effective(): Release {
        if (spec.binarySize > 0) return spec
        val saved = fromJson(AILinuxRuntimeFiles.readJson(File(directory, "release.json")))
        check(saved.version == spec.version && saved.archiveHash == spec.archiveHash && saved.binarySize > 0)
        return saved
    }

    fun verify() {
        check(installed() && AILinuxRuntimeFiles.sha(binary) == effective().binaryHash) { "Pachet Ziva absent sau corupt. Reinstalează Ziva." }
    }

    fun install(cache: File, cancelled: () -> Boolean, progress: (String) -> Unit) {
        check(cache.isDirectory || cache.mkdirs())
        val previous = directory.exists()
        val needed = spec.archiveSize + UNPACKED_LIMIT + (if (previous) UNPACKED_LIMIT else 0L) + 64L * 1024 * 1024
        check(root.usableSpace >= needed) { "Sunt necesari aproximativ ${needed / (1024 * 1024)} MB liberi pentru instalarea Ziva." }
        val archive = File(cache, "ziva-${UUID.randomUUID()}.zip")
        try {
            progress("Descarc Ziva de la furnizor…")
            AIDownload.fetch(spec.url, spec.archiveSize, archive, cancelled, progress, "Ziva")
            progress("Verific pachetul Ziva…")
            extract(archive, cancelled)
        } finally { archive.delete() }
    }

    fun extract(archive: File, cancelled: () -> Boolean = { false }) {
        check(archive.length() == spec.archiveSize && AILinuxRuntimeFiles.sha(archive) == spec.archiveHash) { "Verificarea SHA-256 Ziva a eșuat." }
        val target = directory
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        cleanup(target.parentFile!!)
        val staging = File(target.parentFile, "staging-${UUID.randomUUID()}")
        check(staging.mkdir())
        try {
            var count = 0
            var total = 0L
            val names = HashSet<String>()
            ZipFile(archive).use { zip ->
                for (entry in zip.entries()) {
                    if (entry.isDirectory || !entry.name.startsWith(PREFIX)) continue
                    check(!cancelled()) { "Operație anulată." }
                    val name = relative(entry.name)
                    check(names.add(name)) { "Fișier Ziva duplicat." }
                    check(entry.size in 0..MAX_FILE) { "Fișier Ziva invalid." }
                    total += entry.size
                    check(total <= UNPACKED_LIMIT && ++count <= MAX_FILES) { "Pachetul Ziva este prea mare." }
                    val file = File(staging, "$ADDON/$name")
                    check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs()) { "Structură Ziva invalidă." }
                    zip.getInputStream(entry).use { input -> file.outputStream().use { output ->
                        val buffer = ByteArray(65536); var copied = 0L
                        while (true) {
                            check(!cancelled()) { "Operație anulată." }
                            val read = input.read(buffer); if (read < 0) break
                            copied += read; check(copied <= entry.size) { "Fișier Ziva prea mare." }
                            output.write(buffer, 0, read)
                        }
                        check(copied == entry.size) { "Fișier Ziva incomplet." }
                    } }
                    if (name.startsWith("bin/") || name.startsWith("bin-deps/") || name.startsWith("zivacode/")) {
                        check(file.setExecutable(true, false)) { "Permisiunile Ziva nu pot fi setate." }
                    }
                }
            }
            check(count > 0) { "Arhiva Ziva nu conține pluginul." }
            check(spec.member.startsWith(PREFIX)) { "Executabil Ziva invalid." }
            val executable = File(staging, spec.member)
            check(executable.isFile && executable.length() in 1..MAX_FILE) { "Executabil Ziva absent." }
            val binaryHash = AILinuxRuntimeFiles.sha(executable)
            check(spec.binarySize == 0L || (executable.length() == spec.binarySize && binaryHash == spec.binaryHash)) {
                "Executabil Ziva corupt."
            }
            val verified = spec.copy(binarySize = executable.length(), binaryHash = binaryHash)
            AILinuxRuntimeFiles.writeJson(File(staging, "release.json"), verified.json())
            check(File(staging, "$ADDON/ziva_agent.gdextension").isFile && File(staging, "$ADDON/manifest.json").isFile &&
                File(staging, "$ADDON/LICENSE.md").isFile) { "Structură Ziva invalidă." }
            check(!cancelled()) { "Operație anulată." }
            // Retain the previous addon until the replacement has passed all checks.
            val previous = File(target.parentFile, "previous-${UUID.randomUUID()}")
            val hadPrevious = target.exists()
            if (hadPrevious) check(target.renameTo(previous)) { "Instalarea Ziva existentă nu a putut fi păstrată." }
            if (!staging.renameTo(target)) {
                if (hadPrevious) check(previous.renameTo(target)) { "Instalarea Ziva trebuie reparată." }
                error("Pachetul Ziva nu a putut fi activat.")
            }
            spec = verified
            if (hadPrevious) AILinuxRuntimeFiles.deleteTree(previous)
        } finally { AILinuxRuntimeFiles.deleteTree(staging) }
    }

    private fun relative(name: String): String {
        require(name.startsWith(PREFIX) && name.length > PREFIX.length)
        val value = name.substring(PREFIX.length)
        require(value.length <= 512 && !value.contains('\\') && !value.contains('\u0000'))
        require(value.split('/').none { it.isEmpty() || it == "." || it == ".." }) { "Cale Ziva invalidă." }
        return value
    }

    private fun cleanup(directory: File) {
        for (orphan in directory.listFiles().orEmpty()) {
            if (orphan.name.matches(Regex("(staging|previous)-[a-f0-9-]{36}"))) AILinuxRuntimeFiles.deleteTree(orphan)
        }
    }
}
