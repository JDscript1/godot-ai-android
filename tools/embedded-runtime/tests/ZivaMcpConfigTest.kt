import org.godotengine.editor.AIZivaMcpConfig
import java.io.File
import java.nio.file.Files
import org.json.JSONObject

fun main() {
    val scratch = Files.createTempDirectory("ziva-mcp-config-").toFile()
    var checks = 0
    fun verify(value: Boolean) { check(value); checks++ }
    fun reject(block: () -> Unit) { var rejected = false; try { block() } catch (_: Exception) { rejected = true }; verify(rejected) }
    try {
        val project = File(scratch, "project").apply { mkdirs() }
        val recovery = File(scratch, "private")
        val config = AIZivaMcpConfig(project, recovery)
        val file = File(project, ".mcp.json")
        config.prepare(31001)
        verify(file.readText().contains("\${GODOT_AI_EDITOR_MCP_TOKEN}"))
        verify(config.restore() && !file.exists())
        val original = "{\n \"mcpServers\":{\"other\":{\"url\":\"https://example.invalid/mcp\"}},\"preferences\":true\n}\n"
        file.writeText(original)
        config.prepare(31002)
        verify(JSONObject(file.readText()).getJSONObject("mcpServers").has("other"))
        verify(config.restore() && file.readText() == original)
        config.prepare(31003)
        val edited = JSONObject(file.readText()).put("user_edit", true)
        file.writeText(edited.toString())
        verify(config.restore() && JSONObject(file.readText()).getBoolean("user_edit") && !JSONObject(file.readText()).getJSONObject("mcpServers").has(AIZivaMcpConfig.SERVER))
        file.writeText(original)
        config.prepare(31004)
        val ownedEdit = JSONObject(file.readText())
        ownedEdit.getJSONObject("mcpServers").getJSONObject(AIZivaMcpConfig.SERVER).put("url", "http://127.0.0.1:9999/mcp")
        file.writeText(ownedEdit.toString())
        verify(!config.restore() && file.readText() == ownedEdit.toString())
        reject { config.prepare(31005) }
        ownedEdit.getJSONObject("mcpServers").remove(AIZivaMcpConfig.SERVER)
        file.writeText(ownedEdit.toString())
        verify(config.restore())
        config.prepare(31006)
        // Recover an interrupted previous launch using its private ownership journal.
        AIZivaMcpConfig(project, recovery).prepare(31007)
        verify(JSONObject(file.readText()).getJSONObject("mcpServers").getJSONObject(AIZivaMcpConfig.SERVER).getString("url").contains(":31007/"))
        verify(config.restore())
        file.writeText("{broken")
        reject { config.prepare(31008) }
        verify(file.readText() == "{broken")
        file.delete()
        val outside = File(scratch, "outside").apply { writeText(original) }
        Files.createSymbolicLink(file.toPath(), outside.toPath())
        reject { config.prepare(31009) }
        verify(outside.readText() == original)
        reject { AIZivaMcpConfig.entry(0) }
        println("Ziva MCP config: $checks checks, 0 failures")
    } finally { scratch.deleteRecursively() }
}
