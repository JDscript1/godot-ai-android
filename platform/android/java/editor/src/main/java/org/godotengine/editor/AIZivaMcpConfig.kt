package org.godotengine.editor

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Owns one non-secret project MCP entry. Restores formatting and preserves concurrent user edits. */
class AIZivaMcpConfig(private val project: File, private val recovery: File) {
    companion object {
        const val SERVER = "godot_ai_editor"
        const val TOKEN_ENV = "GODOT_AI_EDITOR_MCP_TOKEN"
        fun entry(port: Int): JSONObject {
            require(port in 1024..65535) { "Port MCP invalid." }
            return JSONObject().put("url", "http://127.0.0.1:$port/mcp")
                .put("headers", JSONObject().put("Authorization", "Bearer \${$TOKEN_ENV}"))
        }
    }
    private val target = File(project, ".mcp.json")
    private val journal = File(recovery, "mcp-config.json")
    private fun read(file: File): String? {
        check(!Files.isSymbolicLink(file.toPath())) { "Configurație MCP prin legătură simbolică; fișierul este păstrat." }
        if (!file.exists()) return null
        check(file.isFile && file.length() <= if (file == journal) 4194304 else 1048576) { "Configurație MCP invalidă sau prea mare." }
        return file.readText(Charsets.UTF_8)
    }
    private fun parse(text: String?): JSONObject = try { if (text == null) JSONObject() else JSONObject(text) }
        catch (_: Exception) { error("Configurație MCP JSON invalidă. Originalul este păstrat.") }
    private fun same(a: JSONObject, b: JSONObject): Boolean =
        a.keys().asSequence().toSet() == b.keys().asSequence().toSet() && a.keys().asSequence().all { key ->
            val left = a.get(key); val right = b.get(key)
            if (left is JSONObject && right is JSONObject) same(left, right) else left == right
        }
    private fun servers(document: JSONObject): JSONObject {
        if (!document.has("mcpServers")) document.put("mcpServers", JSONObject())
        return document.optJSONObject("mcpServers") ?: error("Configurație MCP invalidă: mcpServers trebuie să fie un obiect JSON. Originalul este păstrat.")
    }
    private fun write(file: File, text: String) {
        check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
        val temp = Files.createTempFile(file.parentFile!!.toPath(), ".ziva-mcp-", ".tmp")
        try {
            Files.write(temp, text.toByteArray(Charsets.UTF_8))
            Files.move(temp, file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { Files.deleteIfExists(temp) }
    }
    fun prepare(port: Int) {
        if (journal.exists()) restore()
        check(!journal.exists()) { "Configurația MCP Ziva a fost editată. Păstrăm modificările; rezolvă conflictul înainte de reluare." }
        val original = read(target)
        val document = parse(original)
        val list = servers(document)
        check(!list.has(SERVER)) { "Există deja un server MCP numit $SERVER. Redenumește-l înainte de pornirea Ziva." }
        val entry = entry(port)
        list.put(SERVER, entry)
        val installed = document.toString(2) + "\n"
        check(installed.toByteArray(Charsets.UTF_8).size <= 1048576) { "Configurația MCP rezultată depășește 1 MB. Originalul este păstrat." }
        val record = JSONObject().put("original", original ?: JSONObject.NULL).put("installed", installed).put("entry", entry)
        write(journal, record.toString())
        check(read(target) == original) { "Configurația MCP s-a schimbat în timpul pregătirii; fișierul este păstrat." }
        write(target, installed)
    }
    /** Returns false on an edited owned entry; never discards the recovery record in that case. */
    fun restore(): Boolean {
        val text = read(journal) ?: return true
        val record = parse(text)
        val current = read(target)
        val original = if (record.isNull("original")) null else record.getString("original")
        if (current == original) { journal.delete(); return true }
        if (current == record.getString("installed")) {
            if (original == null) Files.deleteIfExists(target.toPath()) else write(target, original)
        } else if (current != null) {
            val document = parse(current)
            val list = servers(document)
            if (list.has(SERVER) && (list.optJSONObject(SERVER) == null || !same(list.getJSONObject(SERVER), record.getJSONObject("entry")))) return false
            if (list.has(SERVER)) {
                list.remove(SERVER)
                check(read(target) == current) { "Configurația MCP s-a schimbat în timpul restaurării." }
                write(target, document.toString(2) + "\n")
            }
        }
        check(journal.delete()) { "Jurnalul MCP nu poate fi închis." }
        return true
    }
}
