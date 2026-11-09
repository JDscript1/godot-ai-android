package org.godotengine.editor

import android.content.res.AssetManager
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * A Ziva-only Terrain3D overlay.
 *
 * The Android project keeps its Android ARM64 Terrain3D binaries for the native
 * editor/agent. Ziva gets a private copy of the same addon with Linux ARM64
 * binaries supplied by the APK and mounted over /workspace/addons/terrain_3d.
 */
object AIZivaTerrain {
    private const val ADDON = "addons/terrain_3d"
    private const val ASSET_DIR = "terrain3d/linux_arm64"
    private const val DEBUG_LINE =
        "linux.debug.arm64 = \"res://addons/terrain_3d/bin/libterrain.linux.debug.arm64.so\""
    private const val RELEASE_LINE =
        "linux.release.arm64 = \"res://addons/terrain_3d/bin/libterrain.linux.release.arm64.so\""
    private val DEBUG_PATTERN =
        Regex("""(?m)^[ \t]*#?[ \t]*linux\.debug\.arm64[ \t]*=.*$""")
    private val RELEASE_PATTERN =
        Regex("""(?m)^[ \t]*#?[ \t]*linux\.release\.arm64[ \t]*=.*$""")
    private val LIBRARIES = listOf(
        "libterrain.linux.debug.arm64.so",
        "libterrain.linux.release.arm64.so",
    )

    fun prepare(project: File, target: File, assets: AssetManager): File? {
        val source = File(project, ADDON)
        if (!File(source, "terrain.gdextension").isFile) return null
        check(!Files.isSymbolicLink(source.toPath())) { "Addon Terrain3D nesigur." }
        check(!Files.isSymbolicLink(target.toPath())) { "Suprapunerea Terrain3D este nesigură." }
        check(target.isDirectory || target.mkdirs()) { "Suprapunerea Terrain3D nu poate fi creată." }
        copyContents(source, target)
        val config = File(target, "terrain.gdextension")
        var text = config.readText()
        text = ensureLinuxLines(text)
        config.writeText(text)
        val bin = File(target, "bin")
        check(bin.isDirectory || bin.mkdirs()) { "Directorul bin Terrain3D nu poate fi creat." }
        for (name in LIBRARIES) {
            assets.open("$ASSET_DIR/$name").use { input ->
                File(bin, name).outputStream().use { output -> input.copyTo(output) }
            }
            check(File(bin, name).setExecutable(true, false)) { "Permisiunile Terrain3D nu pot fi setate." }
        }
        return target
    }

    private fun ensureLinuxLines(source: String): String {
        var sawDebug = false
        var sawRelease = false
        var text = DEBUG_PATTERN.replace(source) {
            sawDebug = true
            DEBUG_LINE
        }
        text = RELEASE_PATTERN.replace(text) {
            sawRelease = true
            RELEASE_LINE
        }
        val missing = buildList {
            if (!sawDebug) add(DEBUG_LINE)
            if (!sawRelease) add(RELEASE_LINE)
        }
        if (missing.isEmpty()) return text
        return text.trimEnd() + "\n" + missing.joinToString("\n") + "\n"
    }

    private fun copyContents(source: File, target: File) {
        for (file in source.listFiles().orEmpty()) {
            if (file.name == "bin") continue
            check(!Files.isSymbolicLink(file.toPath())) { "Addon Terrain3D conține o legătură nesigură." }
            val output = File(target, file.name)
            if (file.isDirectory) {
                check(output.isDirectory || output.mkdirs()) { "Director Terrain3D invalid." }
                copyContents(file, output)
            } else if (file.isFile) {
                Files.copy(file.toPath(), output.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        }
    }
}
