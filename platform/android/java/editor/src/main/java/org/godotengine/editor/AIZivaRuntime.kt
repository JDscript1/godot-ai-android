package org.godotengine.editor

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Independent Ziva control plane. Never forwards prompts, tokens or settings to our harness. */
object AIZivaRuntime {
    internal fun directory(context: Context) = File(context.noBackupFilesDir, "ai-ziva").apply { mkdirs() }
    internal fun stateFile(context: Context) = File(directory(context), "state.json")
    internal fun cancelFile(context: Context) = File(directory(context), "cancel")
    internal fun read(context: Context) = AILinuxRuntimeFiles.readJson(stateFile(context))
    internal fun save(context: Context, state: JSONObject) {
        state.put("heartbeat", System.currentTimeMillis())
        AILinuxRuntimeFiles.writeJson(stateFile(context), state)
    }
    internal fun projectId(project: File): String = MessageDigest.getInstance("SHA-256").digest(project.canonicalPath.toByteArray())
        .joinToString("") { "%02x".format(it.toInt() and 255) }.take(24)

    fun isBusy(context: Context): Boolean {
        val state = read(context)
        return state.optString("status") in listOf("queued", "installing", "starting", "running", "stopping") &&
            System.currentTimeMillis() - state.optLong("heartbeat") < 45000
    }

    fun status(context: Context): JSONObject {
        val state = read(context)
        val root = AILinuxRuntime.core(context).root
        val installed = AIZivaPackage(root).installed() && AIZivaGodot(root).installed()
        if (!isBusy(context) && state.optString("status") in listOf("queued", "installing", "starting", "running", "stopping")) {
            state.put("status", "interrupted").put("message", "Ziva s-a întrerupt. Poți relua pornirea.")
        }
        if (isBusy(context) && cancelFile(context).exists()) state.put("status", "stopping").put("message", "Opresc Ziva…")
        return state.put("ok", true).put("enabled", BuildConfig.GODOT_AI_ZIVA).put("installed", installed)
            .put("version", AIZivaPackage.RELEASE.version).put("running", state.optString("status") == "running")
            .put("ready", state.optString("status") == "running").put("ui_port", state.optInt("ui_port", 0))
            .put("busy", isBusy(context))
    }

    @Synchronized fun command(context: Context, action: String, args: JSONObject): JSONObject {
        if (action == "ziva_status") {
            val state = status(context)
            val project = args.optString("project_directory")
            val same = project.isNotBlank() && projectId(File(project)) == state.optString("project_id")
            return state.put("same_project", same)
        }
        check(BuildConfig.GODOT_AI_ZIVA) { "Ziva este disponibil în pachetul separat Godot AI Ziva." }
        if (action == "ziva_stop") {
            if (isBusy(context)) cancelFile(context).writeText("stop")
            return JSONObject().put("ok", true)
        }
        if (action == "ziva_open") {
            val state = status(context)
            check(state.optBoolean("running")) { "Pornește mai întâi Ziva." }
            val project = File(args.getString("project_directory")).canonicalFile
            check(projectId(project) == state.optString("project_id")) { "Ziva rulează pentru alt proiect. Oprește-l înainte de schimbare." }
            val port = state.optInt("ui_port", 0)
            check(port in 1..65535) { "Interfața Ziva nu este disponibilă. Reia pornirea." }
            AIZivaWindow.open(port)
            return JSONObject().put("ok", true)
        }
        check(action in listOf("ziva_install", "ziva_start")) { "Operație Ziva necunoscută." }
        check(!isBusy(context)) { "Ziva este deja în lucru. Oprește sesiunea curentă înainte de reluare." }
        check(AILinuxRuntime.core(context).state().optBoolean("ready")) { "Pregătește mai întâi Runtime Linux din Integrări." }
        val linux = JSONObject(AILinuxRuntime.command("status", "{}"))
        check(linux.optString("active_job").isEmpty()) { "Așteaptă încheierea sarcinii Linux." }
        val intent = Intent(context, AIZivaService::class.java).putExtra("action", action)
        val state = JSONObject().put("status", "queued").put("message", "Pregătesc Ziva…")
        if (action == "ziva_start") {
            val project = File(args.getString("project_directory")).canonicalFile
            check(project.isAbsolute && File(project, "project.godot").isFile && !project.path.contains(':')) { "Deschide un proiect Godot pentru Ziva." }
            state.put("project_id", projectId(project))
            intent.putExtra("project_directory", project.path)
        }
        cancelFile(context).delete()
        save(context, state)
        try { context.startForegroundService(intent) }
        catch (error: Exception) {
            save(context, state.put("status", "error").put("message", "Serviciul Ziva nu a pornit."))
            throw error
        }
        return JSONObject().put("ok", true).put("status", "queued")
    }
}
