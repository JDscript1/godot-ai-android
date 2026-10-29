import org.godotengine.editor.AIZivaPackage
import org.godotengine.editor.AILinuxRuntimeFiles
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

fun main() {
    val scratch = Files.createTempDirectory("godot-ziva-package-").toFile()
    var checks = 0
    fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    fun archive(name: String, payload: ByteArray, license: Boolean = true): Pair<File, AIZivaPackage.Release> {
        val zip = File(scratch, "$name.zip")
        ZipOutputStream(zip.outputStream()).use { out ->
            out.putNextEntry(ZipEntry("bin/zivacode")); out.write(payload); out.closeEntry()
            if (license) { out.putNextEntry(ZipEntry("addons/ziva_agent/LICENSE.md")); out.write("Fixture license".toByteArray()); out.closeEntry() }
            // Ignored member must never be interpreted as a path by the extractor.
            out.putNextEntry(ZipEntry("../../outside.txt")); out.write("untrusted".toByteArray()); out.closeEntry()
        }
        return zip to AIZivaPackage.Release("v3.3.2", "https://example.invalid/fixture", zip.length(), AILinuxRuntimeFiles.sha(zip),
            "bin/zivacode", payload.size.toLong(), hash(payload))
    }
    fun reject(block: () -> Unit) {
        var rejected = false
        try { block() } catch (_: IllegalStateException) { rejected = true } catch (_: IllegalArgumentException) { rejected = true }
        check(rejected); checks++
    }
    try {
        val root = File(scratch, "linux").apply { mkdirs() }
        val (zip, spec) = archive("good", "fixture ELF".toByteArray())
        val distribution = AIZivaPackage(root, spec)
        check(!distribution.installed()); checks++
        distribution.extract(zip)
        distribution.verify()
        check(distribution.installed() && distribution.binary.readText() == "fixture ELF"); checks++
        check(File(distribution.binary.parentFile, "LICENSE.md").isFile && !File(scratch, "outside.txt").exists()); checks++
        val history = File(root, "var/lib/godot-ai-ziva/project/history.db").apply { parentFile.mkdirs(); writeText("KEEP") }
        distribution.binary.writeText("corrupted!!")
        reject { distribution.verify() }
        distribution.extract(zip)
        distribution.verify()
        check(history.readText() == "KEEP"); checks++
        reject { AIZivaPackage(root, spec.copy(archiveHash = "0".repeat(64))).extract(zip) }
        check(distribution.binary.readText() == "fixture ELF"); checks++
        reject { AIZivaPackage(File(scratch, "cancelled").apply { mkdirs() }, spec).extract(zip) { true } }
        val (missing, missingSpec) = archive("missing-license", "x".toByteArray(), false)
        reject { AIZivaPackage(File(scratch, "missing").apply { mkdirs() }, missingSpec).extract(missing) }
        reject { AIZivaPackage(root, spec.copy(version = "../../outside")).extract(zip) }
        val unsafe = File(scratch, "unsafe").apply { mkdirs() }
        Files.createSymbolicLink(File(unsafe, "opt").toPath(), File(scratch, "target").apply { mkdirs() }.toPath())
        reject { AIZivaPackage(unsafe, spec).extract(zip) }
        reject { AIZivaPackage(File(scratch, "bad-binary").apply { mkdirs() }, spec.copy(binaryHash = "0".repeat(64))).extract(zip) }
        check(File(scratch, "bad-binary/opt/godot-tools/ziva").listFiles().orEmpty().isEmpty()); checks++
        println("Ziva package: $checks checks, 0 failures")
    } finally { AILinuxRuntimeFiles.deleteTree(scratch) }
}
