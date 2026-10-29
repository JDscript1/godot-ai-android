import org.godotengine.editor.AILinuxRuntimeFiles
import org.godotengine.editor.AIZivaGodot
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

fun main() {
    val scratch = Files.createTempDirectory("godot-ziva-engine-").toFile()
    var checks = 0
    val member = "Godot_v4.7.2-stable_linux.arm64"
    val payload = "fixture GODOT".toByteArray()

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

    fun release(archive: File, binary: ByteArray) = AIZivaGodot.Release("4.7.2",
        "https://example.invalid/godot", archive.length(), AILinuxRuntimeFiles.sha(archive), member,
        binary.size.toLong(), hash(binary))

    fun reject(block: () -> Unit) {
        var rejected = false
        try { block() } catch (_: IllegalStateException) { rejected = true } catch (_: IllegalArgumentException) { rejected = true }
        check(rejected); checks++
    }

    try {
        val root = File(scratch, "linux").apply { mkdirs() }
        val good = zip("good", listOf(member to payload, "LICENSE.txt" to "Godot license".toByteArray()))
        val spec = release(good, payload)
        val distribution = AIZivaGodot(root, spec)
        check(!distribution.installed()); checks++
        distribution.extract(good)
        distribution.verify()
        check(distribution.installed() && distribution.binary.readText() == "fixture GODOT"); checks++
        check(distribution.binary.parentFile.name == "4.7.2" && distribution.guestBinary == "/opt/godot-tools/godot/4.7.2/godot"); checks++
        check(distribution.binary.canExecute()); checks++

        val history = File(root, "var/lib/godot-ai-ziva/project/history.db").apply { parentFile.mkdirs(); writeText("KEEP") }
        distribution.binary.writeText("broken")
        check(!distribution.installed()); checks++
        distribution.extract(good)
        distribution.verify()
        check(history.readText() == "KEEP" && distribution.binary.readText() == "fixture GODOT"); checks++

        reject { AIZivaGodot(root, spec.copy(archiveHash = "0".repeat(64))).extract(good) }
        check(distribution.binary.readText() == "fixture GODOT"); checks++

        val cancelled = AIZivaGodot(File(scratch, "cancelled").apply { mkdirs() }, spec)
        reject { cancelled.extract(good) { true } }
        check(!cancelled.installed()); checks++

        val missing = zip("missing", listOf("LICENSE.txt" to "Godot license".toByteArray()))
        reject { AIZivaGodot(File(scratch, "missing").apply { mkdirs() }, release(missing, payload)).extract(missing) }

        val wrongSize = AIZivaGodot(File(scratch, "wrong-size").apply { mkdirs() }, spec.copy(binarySize = payload.size + 1L))
        reject { wrongSize.extract(good) }
        check(!wrongSize.installed()); checks++

        reject { AIZivaGodot(root, spec.copy(version = "../../outside")).extract(good) }

        val unsafe = File(scratch, "unsafe").apply { mkdirs() }
        Files.createSymbolicLink(File(unsafe, "opt").toPath(), File(scratch, "target").apply { mkdirs() }.toPath())
        reject { AIZivaGodot(unsafe, spec).extract(good) }

        val broken = File(scratch, "bad-binary").apply { mkdirs() }
        reject { AIZivaGodot(broken, spec.copy(binaryHash = "0".repeat(64))).extract(good) }
        check(!File(broken, "opt/godot-tools/godot/4.7.2").exists() &&
            File(broken, "opt/godot-tools/godot").listFiles().orEmpty().isEmpty()); checks++

        val upgrade = zip("upgrade", listOf(member to "upgrade GODOT".toByteArray()))
        reject { AIZivaGodot(root, release(upgrade, "upgrade GODOT".toByteArray()).copy(binaryHash = "0".repeat(64))).extract(upgrade) }
        check(distribution.installed() && distribution.binary.readText() == "fixture GODOT"); checks++

        println("Ziva Godot: $checks checks, 0 failures")
    } finally { AILinuxRuntimeFiles.deleteTree(scratch) }
}
