package org.godotengine.editor

import android.app.Activity
import android.app.Dialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.view.WindowManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference

/** Displays the original local Ziva UI. No JavaScript/native privileged bridge is injected. */
object AIZivaWindow {
    private var host = WeakReference<Activity>(null)
    private var window = WeakReference<Dialog>(null)
    fun register(activity: Activity) { host = WeakReference(activity) }
    fun open(port: Int) {
        require(port in 1..65535) { "Portul interfeței Ziva este invalid." }
        val activity = host.get() ?: error("Editorul Android nu este activ.")
        check(!activity.isFinishing && !activity.isDestroyed) { "Editorul Android se închide." }
        activity.runOnUiThread { show(activity, port) }
    }
    private fun show(activity: Activity, port: Int) {
        if (!BuildConfig.GODOT_AI_ZIVA || activity.isFinishing || activity.isDestroyed || !AIZivaRuntime.status(activity).optBoolean("running")) return
        window.get()?.let { if (it.isShowing) return }
        // A Dialog keeps the host Activity and Godot render loop resumed. A second
        // Activity would pause the native editor that executes MCP tool requests.
        val dialog = Dialog(activity, android.R.style.Theme_Material_Dialog_NoActionBar)
        var web: WebView? = null
        val column = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.rgb(20, 23, 32)) }
        val toolbar = LinearLayout(activity)
        toolbar.addView(Button(activity).apply { text = "‹ Godot AI"; setOnClickListener { dialog.dismiss() } })
        toolbar.addView(TextView(activity).apply { text = "Ziva"; textSize = 18f; setTextColor(Color.WHITE); setPadding(16, 14, 16, 14) },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        toolbar.addView(Button(activity).apply { text = "Reîncarcă"; setOnClickListener { web?.reload() } })
        column.addView(toolbar)
        column.addView(TextView(activity).apply {
            text = "Experimental · interfața oficială rulează într-un editor Godot separat, fără afișare."
            setTextColor(Color.rgb(255, 211, 122)); setPadding(16, 8, 16, 8)
        })
        web = WebView(activity).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.setSupportMultipleWindows(true)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (!request.isForMainFrame) return false
                    val url = request.url
                    if (url.scheme == "http" && url.host == "127.0.0.1" && url.port == port && url.userInfo == null) return false
                    external(activity, url)
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
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
            loadUrl("http://127.0.0.1:$port/")
        }
        column.addView(web, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        dialog.setContentView(column)
        dialog.setOnDismissListener { web?.destroy(); web = null; window.clear() }
        dialog.show()
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        window = WeakReference(dialog)
    }
    private fun external(activity: Activity, url: Uri) {
        if (url.scheme != "https" || url.host.isNullOrEmpty() || url.userInfo != null) return
        try { activity.startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (_: Exception) { }
    }
}
