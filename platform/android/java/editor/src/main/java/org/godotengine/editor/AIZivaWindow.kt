package org.godotengine.editor

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.view.Gravity
import android.view.inputmethod.InputMethodManager
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

/** The official frontend, anchored inside the Ziva main tab. No privileged JS bridge. */
object AIZivaWindow {
    private const val FILE_REQUEST = 0x5A49
    private var host = WeakReference<Activity>(null)
    private var anchor = WeakReference<View>(null)
    private var web: WebView? = null
    private var container: FrameLayout? = null
    private var port = 0
    private var bounds = DoubleArray(4)
    private var shown = false
    private var files: ValueCallback<Array<Uri>>? = null
    private val globalLayout = ViewTreeObserver.OnGlobalLayoutListener { position() }
    private val layout = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> position() }

    fun register(activity: Activity, renderView: View? = null) {
        activity.runOnUiThread {
            if (host.get() !== activity) dispose()
            host = WeakReference(activity)
            if (renderView != null && anchor.get() !== renderView) {
                anchor.get()?.removeOnLayoutChangeListener(layout)
                anchor = WeakReference(renderView)
                renderView.addOnLayoutChangeListener(layout)
            }
            position()
        }
    }

    fun embed(uiPort: Int, rectangle: DoubleArray, reload: Boolean) {
        require(uiPort in 1..65535) { "Portul interfeței Ziva este invalid." }
        require(rectangle.size == 4 && rectangle.all { it.isFinite() && it in 0.0..1.0 } &&
            rectangle[2] > 0 && rectangle[3] > 0 && rectangle[0] + rectangle[2] <= 1.001 &&
            rectangle[1] + rectangle[3] <= 1.001) { "Încadrarea interfeței Ziva este invalidă." }
        val activity = host.get() ?: error("Editorul Android nu este activ.")
        check(!activity.isFinishing && !activity.isDestroyed && anchor.get() != null) { "Suprafața editorului nu este pregătită." }
        activity.runOnUiThread {
            if (host.get() !== activity || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
            if (!BuildConfig.GODOT_AI_ZIVA || !AIZivaRuntime.status(activity).optBoolean("running")) {
                hide(); return@runOnUiThread
            }
            if (port != uiPort) { disposeWeb(); port = uiPort }
            if (web == null) create(activity, uiPort)
            bounds = rectangle.copyOf()
            shown = true
            position()
            if (reload) web?.reload()
        }
    }

    fun hide() {
        host.get()?.runOnUiThread {
            shown = false
            web?.let { browser ->
                if (browser.hasFocus()) (browser.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.hideSoftInputFromWindow(browser.windowToken, 0)
                browser.clearFocus()
            }
            container?.visibility = View.GONE
        }
    }

    fun release(activity: Activity) {
        activity.runOnUiThread {
            if (host.get() === activity) { dispose(); host.clear() }
        }
    }

    private fun create(activity: Activity, uiPort: Int) {
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        val frame = FrameLayout(activity).apply { visibility = View.GONE; setBackgroundColor(Color.rgb(20, 23, 32)) }
        val browser = WebView(activity).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.setSupportMultipleWindows(true)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (!request.isForMainFrame) return false
                    val url = request.url
                    if (url.scheme == "http" && url.host == "127.0.0.1" && url.port == uiPort && url.userInfo == null) return false
                    external(activity, url)
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                    files?.onReceiveValue(null)
                    files = callback
                    return try { activity.startActivityForResult(params.createIntent(), FILE_REQUEST); true }
                    catch (_: Exception) { files = null; false }
                }
                override fun onCreateWindow(view: WebView, dialog: Boolean, userGesture: Boolean, result: android.os.Message): Boolean {
                    if (!userGesture) return false
                    val popup = WebView(activity)
                    popup.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                            external(activity, request.url); view.destroy(); return true
                        }
                    }
                    (result.obj as WebView.WebViewTransport).webView = popup
                    result.sendToTarget()
                    return true
                }
            }
            setDownloadListener { url, _, _, _, _ -> external(activity, Uri.parse(url)) }
            loadUrl("http://127.0.0.1:$uiPort/")
        }
        frame.addView(browser, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(frame, FrameLayout.LayoutParams(1, 1, Gravity.TOP or Gravity.LEFT))
        root.addOnLayoutChangeListener(layout)
        root.viewTreeObserver.addOnGlobalLayoutListener(globalLayout)
        web = browser; container = frame
    }

    // Bounds are normalized against the Godot render surface, not the decor view.
    // This accounts for display scaling, system bars, rotation and the Android IME.
    private fun position() {
        if (host.get() == null) return
        val surface = anchor.get() ?: return
        val frame = container ?: return
        val root = frame.parent as? ViewGroup ?: return
        if (!shown || !surface.isShown || surface.width <= 0 || surface.height <= 0) { frame.visibility = View.GONE; return }
        val origin = IntArray(2); surface.getLocationInWindow(origin)
        val parent = IntArray(2); root.getLocationInWindow(parent)
        val left = origin[0] - parent[0] + (bounds[0] * surface.width).roundToInt()
        val top = origin[1] - parent[1] + (bounds[1] * surface.height).roundToInt()
        val requested = Rect(left, top, left + (bounds[2] * surface.width).roundToInt(), top + (bounds[3] * surface.height).roundToInt())
        val visible = Rect()
        root.getWindowVisibleDisplayFrame(visible)
        val screen = IntArray(2); root.getLocationOnScreen(screen)
        visible.offset(-screen[0], -screen[1])
        if (!requested.intersect(visible) || requested.isEmpty) { frame.visibility = View.GONE; return }
        val current = frame.layoutParams as? FrameLayout.LayoutParams
        if (current == null || current.width != requested.width() || current.height != requested.height() ||
            current.leftMargin != requested.left || current.topMargin != requested.top) {
            frame.layoutParams = FrameLayout.LayoutParams(requested.width(), requested.height(), Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = requested.left; topMargin = requested.top
            }
        }
        frame.visibility = View.VISIBLE
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != FILE_REQUEST) return false
        files?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data)); files = null
        return true
    }

    private fun disposeWeb() {
        files?.onReceiveValue(null); files = null
        (container?.parent as? ViewGroup)?.let { root -> root.removeOnLayoutChangeListener(layout); root.viewTreeObserver.removeOnGlobalLayoutListener(globalLayout); root.removeView(container) }
        web?.stopLoading(); web?.destroy(); web = null; container = null
        port = 0; shown = false
    }
    private fun dispose() {
        disposeWeb()
        anchor.get()?.removeOnLayoutChangeListener(layout); anchor.clear()
    }
    private fun external(activity: Activity, url: Uri) {
        if (url.scheme != "https" || url.host.isNullOrEmpty() || url.userInfo != null) return
        try { activity.startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (_: Exception) { }
    }
}
