package org.godotengine.editor

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import java.lang.ref.WeakReference
import java.net.URI

/** One Android prompt, independent cancellable callers; callbacks run on the UI thread. */
internal class AIMicrophoneRequests {
    private val requests = linkedMapOf<Any, (Boolean) -> Unit>()
    var prompting = false
        private set
    val hasPending: Boolean get() = requests.isNotEmpty()
    fun add(owner: Any, result: (Boolean) -> Unit): Boolean {
        requests.remove(owner)?.invoke(false)
        requests[owner] = result
        if (prompting) return false
        prompting = true
        return true
    }
    fun cancel(owner: Any) { requests.remove(owner)?.invoke(false) }
    fun resolve(granted: Boolean) {
        val callbacks = requests.values.toList()
        requests.clear(); prompting = false
        callbacks.forEach { it(granted) }
    }
}

/** Shared permission handling for native dictation and the official local WebView. */
object AIMicrophonePermission {
    private const val REQUEST = 0x414D
    private var host = WeakReference<Activity>(null)
    private val requests = AIMicrophoneRequests()

    fun request(activity: Activity, owner: Any, result: (Boolean) -> Unit) {
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed) { result(false); return@runOnUiThread }
            if (host.get() !== activity) { requests.resolve(false); host = WeakReference(activity) }
            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                result(true); return@runOnUiThread
            }
            if (requests.add(owner, result)) {
                try { activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST) }
                catch (_: Exception) { requests.resolve(false) }
            }
        }
    }

    fun cancel(owner: Any) { requests.cancel(owner) }

    fun result(activity: Activity, code: Int, permissions: Array<String>, grants: IntArray): Boolean {
        if (code != REQUEST) return false
        if (host.get() !== activity) return true
        val index = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
        val waiting = requests.hasPending
        val granted = index >= 0 && grants.getOrNull(index) == PackageManager.PERMISSION_GRANTED &&
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        requests.resolve(granted)
        if (!granted && waiting && !activity.isFinishing && !activity.isDestroyed &&
            !activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) {
            AlertDialog.Builder(activity).setTitle("Acces la microfon")
                .setMessage("Microfonul este blocat pentru această aplicație. Îl poți activa în Setări Android → Permisiuni → Microfon, apoi apasă din nou microfonul.")
                .setNegativeButton("Anulează", null)
                .setPositiveButton("Setări Android") { _, _ ->
                    try { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))) }
                    catch (_: Exception) { }
                }.show()
        }
        return true
    }

    fun release(activity: Activity) {
        if (host.get() === activity) { requests.resolve(false); host.clear() }
    }

    internal fun localOrigin(value: String?, port: Int): Boolean = try {
        val uri = URI(value ?: "")
        port in 1..65535 && uri.scheme == "http" && uri.host == "127.0.0.1" && uri.port == port && uri.rawUserInfo == null
    } catch (_: Exception) { false }
}
