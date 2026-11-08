package org.godotengine.editor

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.zip.ZipFile

/** Optional upstream download. No Ziva binaries or proprietary UI are redistributed in the APK. */
class AIZivaPackage(private val root: File, private var spec: Release = activeRelease(root)) {
    data class Release(val version: String, val url: String, val archiveSize: Long, val archiveHash: String,
        val member: String, val binarySize: Long, val binaryHash: String,
        val runtimeUrl: String = "", val runtimeSize: Long = 0L, val runtimeHash: String = "") {
        fun json() = JSONObject().put("version", version).put("url", url).put("archive_size", archiveSize)
            .put("archive_hash", archiveHash).put("member", member).put("binary_size", binarySize).put("binary_hash", binaryHash)
            .put("runtime_url", runtimeUrl).put("runtime_size", runtimeSize).put("runtime_hash", runtimeHash)
        val runtimeIsTarZst get() = runtimeUrl.endsWith(".tar.zst")
    }
    companion object {
        private const val ADDON = "addons/ziva_agent"
        private const val PREFIX = "$ADDON/"
        private const val EXTENSION = "bin/linux_arm64/libziva_agent.linux.release.arm64.so"
        private const val MAX_FILE = 320L * 1024 * 1024
        private const val UNPACKED_LIMIT = 768L * 1024 * 1024
        private const val MAX_FILES = 4000
        // Since v3.3.3 the addon archive and the CEF runtime archive are published separately.
        // v3.3.6 publishes the runtime as .tar.zst. The binary metadata is
        // intentionally left empty here and recorded after verified extraction.
        val RELEASE = Release("v3.3.6",
            "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/v3.3.6/ziva-ai-agent-v3.3.6-godot-v4.2.0-linux-arm64.zip",
            3072316, "4d0ae701c8d93b7ee40beee92a5b6c5f04179affd75f304fc7f33c155c57d400",
            "$ADDON/zivacode/linux_arm64/zivacode", 0, "",
            "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/v3.3.6/ziva-runtime-v3.3.6-linux-arm64.tar.zst",
            176377796, "0904b6b3d4254d7a0dcb993b34140cc25d0527ca99bcd3319c87dc397476facd")
        fun fromJson(json: JSONObject): Release {
            val version = json.getString("version")
            require(version.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+"))) { "Versiune Ziva invalidă." }
            val expected = "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/$version/ziva-ai-agent-$version-godot-v4.2.0-linux-arm64.zip"
            require(json.getString("url") == expected) { "Sursă Ziva neoficială sau arhitectură incompatibilă." }
            val hash = json.getString("archive_hash")
            val size = json.getLong("archive_size")
            require(hash.matches(Regex("[a-f0-9]{64}")) && size in 1..(512L * 1024 * 1024)) { "Integritate Ziva absentă." }
            val runtimeUrl = json.optString("runtime_url", "")
            val runtimeSize = json.optLong("runtime_size", 0)
            val runtimeHash = json.optString("runtime_hash", "")
            val hasRuntime = runtimeUrl.isNotEmpty() || runtimeSize != 0L || runtimeHash.isNotEmpty()
            if (hasRuntime) {
                val expectedRuntimeZip = "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/$version/ziva-runtime-$version-linux-arm64.zip"
                val expectedRuntimeTarZst = "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/$version/ziva-runtime-$version-linux-arm64.tar.zst"
                require(runtimeUrl == expectedRuntimeZip || runtimeUrl == expectedRuntimeTarZst) { "Componentă Ziva neoficială sau arhitectură incompatibilă." }
                require(runtimeHash.matches(Regex("[a-f0-9]{64}")) && runtimeSize in 1..(512L * 1024 * 1024)) {
                    "Integritate Ziva absentă pentru componentă."
                }
            }
            val member = "$ADDON/zivacode/linux_arm64/zivacode"
            require(json.optString("member", member) == member)
            val binarySize = json.optLong("binary_size", 0)
            val binaryHash = json.optString("binary_hash")
            require((binarySize == 0L && binaryHash.isEmpty()) ||
                (binarySize in 1..MAX_FILE && binaryHash.matches(Regex("[a-f0-9]{64}"))))
            return Release(version, expected, size, hash, member, binarySize, binaryHash,
                if (hasRuntime) runtimeUrl else "", if (hasRuntime) runtimeSize else 0, if (hasRuntime) runtimeHash else "")
        }
        fun activeRelease(root: File): Release {
            val file = File(root, "opt/godot-tools/ziva/active.json")
            if (!file.isFile) return RELEASE
            check(!Files.isSymbolicLink(file.toPath()))
            val stored = fromJson(AILinuxRuntimeFiles.readJson(file)).also { require(it.binarySize > 0) }
            // An older recorded release must not outlive the version pinned by this app.
            return if (newer(RELEASE.version, stored.version)) RELEASE else stored
        }
        private fun newer(candidate: String, current: String): Boolean {
            fun parts(value: String) = value.removePrefix("v").split('.').map { it.toIntOrNull() ?: -1 }
            val a = parts(candidate); val b = parts(current)
            if (a.size != 3 || b.size != 3 || a.any { it < 0 } || b.any { it < 0 }) return false
            for (i in 0..2) if (a[i] != b[i]) return a[i] > b[i]
            return false
        }
    }
    val version get() = spec.version
    val runtimeIsTarZst get() = spec.runtimeUrl.endsWith(".tar.zst")
    val extension get() = "/opt/godot-tools/ziva/$version/$ADDON/$EXTENSION"
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

    /**
     * The extension only accepts its own user://ziva/runtime copy and ignores the overlay
     * installed next to the addon. Seeding it stops a 224 MB self-download that cannot
     * finish inside the session startup deadline.
     */
    fun seedRuntime(userData: File) {
        if (spec.runtimeSize == 0L) return
        check(!Files.isSymbolicLink(userData.toPath())) { "Directorul de date Godot nu este sigur." }
        check(userData.isDirectory || userData.mkdirs()) { "Directorul de date Godot nu poate fi creat." }
        val root = File(userData, "ziva/runtime")
        check(!Files.isSymbolicLink(root.toPath()) && (root.isDirectory || root.mkdirs())) {
            "Directorul runtime Ziva nu poate fi creat."
        }
        cleanRuntime(root)
        val target = File(root, spec.version)
        val marker = File(target, ".ready")
        val ready = if (!Files.isSymbolicLink(target.toPath()) && marker.isFile &&
            !Files.isSymbolicLink(marker.toPath())) try { marker.readText() } catch (_: Exception) { "" } else ""
        if (ready == spec.runtimeHash && seeded(target)) return
        try {
            val staging = File(root, "${spec.version}.seed-${UUID.randomUUID()}")
            check(staging.mkdir()) { "Componenta Ziva nu poate fi pregătită." }
            try {
                copyRuntime(addon, staging)
                check(seeded(staging)) { "Componenta Ziva este incompletă. Reinstalează Ziva." }
                // The extension accepts the pinned runtime SHA-256 as its completion marker.
                File(staging, ".ready").writeText(spec.runtimeHash)
                val previous = File(root, "${spec.version}.old-${UUID.randomUUID()}")
                val hadPrevious = target.exists()
                if (hadPrevious) check(target.renameTo(previous)) { "Componenta Ziva veche nu poate fi păstrată." }
                if (!staging.renameTo(target)) {
                    if (hadPrevious) check(previous.renameTo(target)) { "Componenta Ziva trebuie reparată." }
                    error("Componenta Ziva nu poate fi activată.")
                }
                if (hadPrevious) AILinuxRuntimeFiles.deleteTree(previous)
            } finally { AILinuxRuntimeFiles.deleteTree(staging) }
        } catch (error: IllegalStateException) {
            throw error
        } catch (error: Exception) {
            throw IllegalStateException("Componenta Ziva nu a putut fi pregătită pe dispozitiv.", error)
        }
    }

    private fun seeded(runtime: File): Boolean {
        val root = try { runtime.canonicalFile } catch (_: Exception) { return false }
        return listOf(
            "bin/linux_arm64/libcef.so", "bin/linux_arm64/ziva_cef_helper",
            "bin-deps/linux_arm64/ffmpeg", "zivacode/linux_arm64/zivacode"
        ).all { name ->
            val file = File(runtime, name)
            file.isFile && !Files.isSymbolicLink(file.toPath()) && file.length() > 0 &&
                try { file.canonicalPath.startsWith(root.path + File.separator) } catch (_: Exception) { false }
        }
    }

    private fun cleanRuntime(root: File) {
        val version = Regex.escape(spec.version)
        for (orphan in root.listFiles().orEmpty()) {
            if (orphan.name.startsWith("${spec.version}.download.") || orphan.name.startsWith("${spec.version}.damaged.") ||
                orphan.name.matches(Regex("$version\\.(seed|old)-[a-f0-9-]{36}"))) AILinuxRuntimeFiles.deleteTree(orphan)
        }
    }

    private fun copyRuntime(source: File, destination: File) {
        var count = 0
        var total = 0L
        fun copy(directory: File, prefix: String) {
            for (file in directory.listFiles().orEmpty().sortedBy { it.name }) {
                val name = "$prefix/${file.name}"
                check(!Files.isSymbolicLink(file.toPath())) { "Componenta Ziva conține o legătură nesigură." }
                if (file.isDirectory) { copy(file, name); continue }
                check(file.isFile) { "Componenta Ziva este incompletă. Reinstalează Ziva." }
                total += file.length()
                check(total <= UNPACKED_LIMIT && ++count <= MAX_FILES) { "Componenta Ziva este prea mare." }
                if (name == EXTENSION) continue
                val output = File(destination, name)
                check(output.parentFile!!.isDirectory || output.parentFile!!.mkdirs()) { "Structură Ziva invalidă." }
                try {
                    Files.createLink(output.toPath(), file.toPath())
                } catch (_: Exception) {
                    check(destination.usableSpace >= file.length() + 16L * 1024 * 1024) {
                        "Spațiu insuficient pentru componenta Ziva."
                    }
                    try {
                        Files.copy(file.toPath(), output.toPath(),
                            StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.COPY_ATTRIBUTES)
                    } catch (_: UnsupportedOperationException) {
                        Files.copy(file.toPath(), output.toPath(), StandardCopyOption.REPLACE_EXISTING)
                    }
                    if (file.canExecute()) check(output.setExecutable(true, false)) {
                        "Permisiunile componentei Ziva nu pot fi setate."
                    }
                }
            }
        }
        for (name in listOf("bin", "bin-deps", "zivacode")) {
            val directory = File(source, name)
            check(directory.isDirectory && !Files.isSymbolicLink(directory.toPath())) {
                "Componenta Ziva lipsește din pachet. Reinstalează Ziva."
            }
            copy(directory, name)
        }
        check(count > 0) { "Componenta Ziva lipsește din pachet. Reinstalează Ziva." }
    }

    fun install(cache: File, cancelled: () -> Boolean, progress: (String) -> Unit,
        extractRuntimeTarZst: ((File, File) -> Unit)? = null) {
        check(cache.isDirectory || cache.mkdirs())
        val previous = directory.exists()
        val needed = spec.archiveSize + spec.runtimeSize + UNPACKED_LIMIT + (if (previous) UNPACKED_LIMIT else 0L) + 64L * 1024 * 1024
        check(root.usableSpace >= needed) { "Sunt necesari aproximativ ${needed / (1024 * 1024)} MB liberi pentru instalarea Ziva." }
        val archive = File(cache, "ziva-${UUID.randomUUID()}.zip")
        val runtime = if (spec.runtimeSize > 0) {
            val suffix = if (spec.runtimeIsTarZst) ".tar.zst" else ".zip"
            File(cache, "ziva-runtime-${UUID.randomUUID()}$suffix")
        } else null
        try {
            progress("Descarc Ziva de la furnizor…")
            AIDownload.fetch(spec.url, spec.archiveSize, archive, cancelled, progress, "Ziva")
            if (runtime != null) {
                progress("Descarc componenta Ziva…")
                AIDownload.fetch(spec.runtimeUrl, spec.runtimeSize, runtime, cancelled, progress, "Ziva runtime")
            }
            progress("Verific pachetul Ziva…")
            extract(archive, runtime, cancelled, extractRuntimeTarZst)
        } finally { archive.delete(); runtime?.delete() }
    }

    fun extract(archive: File, runtime: File? = null, cancelled: () -> Boolean = { false },
        extractRuntimeTarZst: ((File, File) -> Unit)? = null) {
        check(archive.length() == spec.archiveSize && AILinuxRuntimeFiles.sha(archive) == spec.archiveHash) { "Verificarea SHA-256 Ziva a eșuat." }
        if (spec.runtimeSize > 0) {
            check(runtime != null && runtime.isFile && runtime.length() == spec.runtimeSize &&
                AILinuxRuntimeFiles.sha(runtime) == spec.runtimeHash) { "Verificarea SHA-256 a componentei Ziva a eșuat." }
        } else check(runtime == null) { "Componentă Ziva neașteptată." }
        val target = directory
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        cleanup(target.parentFile!!)
        val staging = File(target.parentFile, "staging-${UUID.randomUUID()}")
        check(staging.mkdir())
        try {
            var count = 0
            var total = 0L
            val names = HashSet<String>()
            fun unpack(file: File, runtimeArchive: Boolean) {
                ZipFile(file).use { zip ->
                    for (entry in zip.entries()) {
                        if (entry.isDirectory) continue
                        // The runtime archive is rooted at the addon directory itself.
                        val full = when {
                            entry.name.startsWith(PREFIX) -> entry.name
                            runtimeArchive -> PREFIX + entry.name
                            else -> continue
                        }
                        check(!cancelled()) { "Operație anulată." }
                        val name = relative(full)
                        check(names.add(name)) { "Fișier Ziva duplicat." }
                        check(entry.size in 0..MAX_FILE) { "Fișier Ziva invalid." }
                        total += entry.size
                        check(total <= UNPACKED_LIMIT && ++count <= MAX_FILES) { "Pachetul Ziva este prea mare." }
                        val output = File(staging, "$ADDON/$name")
                        check(output.parentFile!!.isDirectory || output.parentFile!!.mkdirs()) { "Structură Ziva invalidă." }
                        zip.getInputStream(entry).use { input -> output.outputStream().use { stream ->
                            val buffer = ByteArray(65536); var copied = 0L
                            while (true) {
                                check(!cancelled()) { "Operație anulată." }
                                val read = input.read(buffer); if (read < 0) break
                                copied += read; check(copied <= entry.size) { "Fișier Ziva prea mare." }
                                stream.write(buffer, 0, read)
                            }
                            check(copied == entry.size) { "Fișier Ziva incomplet." }
                        } }
                        if (name.startsWith("bin/") || name.startsWith("bin-deps/") || name.startsWith("zivacode/")) {
                            check(output.setExecutable(true, false)) { "Permisiunile Ziva nu pot fi setate." }
                        }
                    }
                }
            }
            unpack(archive, false)
            if (runtime != null) {
                if (spec.runtimeIsTarZst) {
                    check(extractRuntimeTarZst != null) {
                        "Extractorul tar.zst pentru componenta Ziva nu este disponibil."
                    }
                    extractRuntimeTarZst(runtime, staging)
                    for (name in listOf(
                        "zivacode/linux_arm64/zivacode",
                        "bin/linux_arm64/ziva_cef_helper",
                        "bin/linux_arm64/libcef.so",
                        "bin-deps/linux_arm64/ffmpeg",
                        "bin-deps/linux_arm64/rg",
                        "bin-deps/linux_arm64/git/bin/git",
                    )) {
                        val output = File(staging, "$ADDON/$name")
                        if (output.isFile) {
                            check(output.setExecutable(true, false)) { "Permisiunile Ziva nu pot fi setate." }
                        }
                    }
                } else {
                    unpack(runtime, true)
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
