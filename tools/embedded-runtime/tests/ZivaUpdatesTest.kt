import org.godotengine.editor.AIZivaUpdates
import org.godotengine.editor.AIZivaPackage
import org.json.JSONArray
import org.json.JSONObject

fun main() {
    var checks = 0
    val spec = AIZivaPackage.RELEASE
    fun asset() = JSONObject().put("name", spec.url.substringAfterLast('/')).put("browser_download_url", spec.url)
        .put("size", spec.archiveSize).put("digest", "sha256:${spec.archiveHash}")
    fun metadata(value: JSONObject = asset()) = JSONObject().put("tag_name", spec.version).put("assets", JSONArray().put(value))
    fun reject(value: JSONObject) {
        var rejected = false
        try { AIZivaUpdates.release(value) } catch (_: Exception) { rejected = true }
        check(rejected); checks++
    }
    check(AIZivaUpdates.release(metadata()).archiveHash == spec.archiveHash); checks++
    reject(metadata().put("draft", true)); reject(metadata().put("prerelease", true))
    reject(metadata(asset().put("digest", "md5:1234")))
    reject(metadata(asset().put("digest", "sha256:")))
    reject(metadata(asset().put("size", 99999999999L)))
    reject(metadata(asset().put("browser_download_url", "https://evil.invalid/ziva.zip")))
    reject(metadata(asset().put("name", "ziva-linux-x86_64.zip")))
    reject(metadata().put("tag_name", "../../outside"))
    reject(metadata().put("assets", JSONArray().put(asset()).put(asset())))
    check(AIZivaUpdates.newer("v3.10.0", "v3.9.9")); checks++
    check(!AIZivaUpdates.newer("v3.3.2", "v3.3.2") && !AIZivaUpdates.newer("v3.3.1", "v3.3.2")); checks++
    check(!AIZivaUpdates.newer("v3.3.3-beta", "v3.3.2")); checks++
    println("Ziva official updates: $checks checks, 0 failures")
}
