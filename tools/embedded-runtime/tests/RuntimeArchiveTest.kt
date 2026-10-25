import org.godotengine.editor.AILinuxRuntimeFiles
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

fun main() {
    val base = Files.createTempDirectory("godot-linux-unpack-test").toFile()
    var checks = 0
    fun refuse(entries: JSONArray, files: Map<String, ByteArray> = emptyMap()) {
        val archive = File(base, "bad.zip")
        ZipOutputStream(archive.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("manifest.json"))
            zip.write(JSONObject().put("schema", 1).put("architecture", "arm64").put("unpacked_bytes", 0).put("entries", entries).toString().toByteArray())
            zip.closeEntry()
            for ((name, data) in files) { zip.putNextEntry(ZipEntry(name)); zip.write(data); zip.closeEntry() }
        }
        val output = File(base, "extracted")
        val runtime = AILinuxRuntimeFiles(base, base, { error("No assets") })
        var rejected = false
        try { runtime.unpack(archive, output) } catch (_: IllegalArgumentException) { rejected = true } catch (_: IllegalStateException) { rejected = true }
        check(rejected) { "Unsafe manifest was accepted: $entries" }
        AILinuxRuntimeFiles.deleteTree(output)
        checks += 1
    }
    try {
        refuse(JSONArray().put(JSONObject().put("path", "../outside").put("type", "directory")))
        refuse(JSONArray().put(JSONObject().put("path", "etc/link").put("type", "symlink").put("target", "../../../outside")))
        refuse(JSONArray().put(JSONObject().put("path", "bin").put("type", "symlink").put("target", "usr/bin"))
            .put(JSONObject().put("path", "bin/child").put("type", "directory")))
        refuse(JSONArray().put(JSONObject().put("path", "duplicate").put("type", "directory"))
            .put(JSONObject().put("path", "duplicate").put("type", "directory")))
        refuse(JSONArray().put(JSONObject().put("path", "absolute").put("type", "symlink").put("target", "/data/data")))
        refuse(JSONArray().put(JSONObject().put("path", "corrupt").put("type", "file").put("mode", 493).put("size", 0).put("sha256", "f".repeat(64))), mapOf("files/corrupt" to byteArrayOf()))
        println("LINUX_ARCHIVE_TESTS_PASS $checks")
    } finally { AILinuxRuntimeFiles.deleteTree(base) }
}
