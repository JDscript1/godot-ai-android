import org.godotengine.editor.AILinuxRuntimeFiles
import org.godotengine.editor.AIZivaPackage
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

fun main() {
    val scratch = Files.createTempDirectory("godot-ziva-package-").toFile()
    var checks = 0
    val addon = "addons/ziva_agent"
    val member = "$addon/zivacode/linux_arm64/zivacode"
    val payload = "fixture ELF".toByteArray()

    fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }

    fun zip(name: String, entries: List<Pair<String, ByteArray>>): File {
        val archive = File(scratch, "$name.zip")
        ZipOutputStream(archive.outputStream()).use { out ->
            for ((path, data) in entries) {
                out.putNextEntry(ZipEntry(path)); out.write(data); out.closeEntry()
            }
        }
        return archive
    }

    fun release(archive: File, binary: ByteArray) = AIZivaPackage.Release("v3.3.2", "https://example.invalid/fixture",
        archive.length(), AILinuxRuntimeFiles.sha(archive), member, binary.size.toLong(), hash(binary))

    fun entries(binary: ByteArray = payload, license: Boolean = true, gdextension: Boolean = true,
        manifest: Boolean = true, binaryEntry: Boolean = true): List<Pair<String, ByteArray>> {
        val files = mutableListOf<Pair<String, ByteArray>>()
        if (binaryEntry) files += member to binary
        files += "$addon/bin/linux_arm64/libziva.so" to "runtime".toByteArray()
        files += "$addon/zivacode/linux_arm64/zivacode-helper" to "helper".toByteArray()
        if (gdextension) files += "$addon/ziva_agent.gdextension" to "[configuration]\n".toByteArray()
        if (manifest) files += "$addon/manifest.json" to "{\"version\":\"v3.3.2\"}".toByteArray()
        if (license) files += "$addon/LICENSE.md" to "Fixture license".toByteArray()
        // Entries outside the addon prefix are ignored, never interpreted as paths.
        files += "bin/zivacode" to "decoy".toByteArray()
        files += "../../outside.txt" to "untrusted".toByteArray()
        return files
    }

    fun reject(block: () -> Unit) {
        var rejected = false
        try { block() } catch (_: IllegalStateException) { rejected = true } catch (_: IllegalArgumentException) { rejected = true }
        check(rejected); checks++
    }

    try {
        val root = File(scratch, "linux").apply { mkdirs() }
        val good = zip("good", entries())
        val spec = release(good, payload)
        val distribution = AIZivaPackage(root, spec)
        check(!distribution.installed()); checks++
        distribution.extract(good)
        distribution.verify()
        check(distribution.installed() && distribution.binary.readText() == "fixture ELF"); checks++
        check(File(distribution.addon, "ziva_agent.gdextension").isFile &&
            File(distribution.addon, "manifest.json").isFile && File(distribution.addon, "LICENSE.md").isFile); checks++
        check(distribution.binary.canExecute() &&
            File(distribution.addon, "bin/linux_arm64/libziva.so").canExecute()); checks++
        check(!File(distribution.addon, "bin/zivacode").exists() &&
            !File(distribution.addon.parentFile, "bin/zivacode").exists() && !File(scratch, "outside.txt").exists()); checks++

        val history = File(root, "var/lib/godot-ai-ziva/project/history.db").apply { parentFile.mkdirs(); writeText("KEEP") }
        distribution.binary.writeText("corrupt".padEnd(payload.size, '!'))
        reject { distribution.verify() }
        distribution.extract(good)
        distribution.verify()
        check(history.readText() == "KEEP" && distribution.binary.readText() == "fixture ELF"); checks++

        reject { AIZivaPackage(root, spec.copy(archiveHash = "0".repeat(64))).extract(good) }
        check(distribution.binary.readText() == "fixture ELF"); checks++

        val cancelled = AIZivaPackage(File(scratch, "cancelled").apply { mkdirs() }, spec)
        reject { cancelled.extract(good) { true } }
        check(!cancelled.installed()); checks++

        for ((name, files) in listOf(
            "no-license" to entries(license = false),
            "no-gdextension" to entries(gdextension = false),
            "no-manifest" to entries(manifest = false),
            "no-binary" to entries(binaryEntry = false))) {
            val archive = zip(name, files)
            val target = AIZivaPackage(File(scratch, name).apply { mkdirs() }, release(archive, payload))
            reject { target.extract(archive) }
            check(!target.installed()); checks++
        }
        val empty = zip("empty", listOf("bin/zivacode" to "decoy".toByteArray()))
        reject { AIZivaPackage(File(scratch, "empty").apply { mkdirs() }, release(empty, payload)).extract(empty) }

        for ((name, path) in listOf("dotdot" to "$addon/../evil.txt", "backslash" to "$addon/..\\evil.txt",
            "blank" to "$addon//evil.txt")) {
            val archive = zip(name, entries() + (path to "evil".toByteArray()))
            val target = AIZivaPackage(File(scratch, name).apply { mkdirs() }, release(archive, payload))
            reject { target.extract(archive) }
            check(!target.installed()); checks++
        }

        reject { AIZivaPackage(root, spec.copy(version = "../../outside")).extract(good) }

        val unsafe = File(scratch, "unsafe").apply { mkdirs() }
        Files.createSymbolicLink(File(unsafe, "opt").toPath(), File(scratch, "target").apply { mkdirs() }.toPath())
        reject { AIZivaPackage(unsafe, spec).extract(good) }

        val broken = File(scratch, "bad-binary").apply { mkdirs() }
        reject { AIZivaPackage(broken, spec.copy(binaryHash = "0".repeat(64))).extract(good) }
        check(!File(broken, "opt/godot-tools/ziva/v3.3.2").exists() &&
            File(broken, "opt/godot-tools/ziva").listFiles().orEmpty().isEmpty()); checks++

        val upgrade = zip("upgrade", entries(binary = "upgrade ELF".toByteArray()))
        reject { AIZivaPackage(root, release(upgrade, "upgrade ELF".toByteArray()).copy(binaryHash = "0".repeat(64))).extract(upgrade) }
        check(distribution.installed() && distribution.binary.readText() == "fixture ELF"); checks++

        val installed = AIZivaPackage(File(scratch, "installed-no-manifest").apply { mkdirs() }, spec)
        installed.extract(good)
        File(installed.addon, "manifest.json").delete()
        check(!installed.installed()); checks++

        println("Ziva package: $checks checks, 0 failures")
    } finally { AILinuxRuntimeFiles.deleteTree(scratch) }
}
