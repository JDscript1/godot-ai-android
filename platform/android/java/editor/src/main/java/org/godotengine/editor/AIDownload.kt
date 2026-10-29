package org.godotengine.editor

import java.io.File
import java.net.HttpURLConnection
import java.net.URI

/** Bounded HTTPS download. Callers verify the bytes before installing them. */
internal object AIDownload {
    fun fetch(url: String, size: Long, destination: File, cancelled: () -> Boolean, progress: (String) -> Unit, label: String) {
        var location = URI(url)
        repeat(6) { redirect ->
            check(!cancelled()) { "Operație anulată." }
            require(location.scheme == "https" && location.userInfo == null)
            val connection = location.toURL().openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15000; connection.readTimeout = 15000
            connection.setRequestProperty("User-Agent", "Godot-AI-Ziva-Installer")
            try {
                if (connection.responseCode in listOf(301, 302, 303, 307, 308)) {
                    check(redirect < 5) { "Prea multe redirecționări la descărcarea $label." }
                    location = location.resolve(connection.getHeaderField("Location") ?: error("Redirecționare invalidă."))
                    return@repeat
                }
                check(connection.responseCode == 200) { "Descărcarea $label a eșuat (HTTP ${connection.responseCode})." }
                val expectedLength = connection.contentLengthLong
                check(expectedLength == -1L || expectedLength == size) { "Dimensiune $label neașteptată." }
                val total = size / (1024 * 1024)
                connection.inputStream.use { input -> destination.outputStream().use { output ->
                    val buffer = ByteArray(65536); var count = 0L; var last = -1L
                    while (true) {
                        check(!cancelled()) { "Operație anulată." }
                        val read = input.read(buffer); if (read < 0) break
                        count += read; check(count <= size) { "Pachetul $label este prea mare." }
                        output.write(buffer, 0, read)
                        val megabytes = count / (1024 * 1024)
                        if (megabytes / 8 != last / 8) { last = megabytes; progress("Descarc $label: $megabytes / $total MB") }
                    }
                    check(count == size) { "Descărcarea $label este incompletă." }
                } }
                return
            } finally { connection.disconnect() }
        }
        error("Descărcarea $label nu s-a finalizat.")
    }
}
