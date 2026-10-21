package org.godotengine.editor

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Editor-only credentials. The AES key is non-exportable and belongs to this APK. */
object AISecretVault {
    private var context: Context? = null
    private const val ALIAS = "godot_ai_assistant_v1"

    fun initialize(value: Context) { context = value.applicationContext }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    @JvmStatic @Synchronized fun store(name: String, value: String): String = try {
        val prefs = requireNotNull(context).getSharedPreferences("ai_assistant_vault", Context.MODE_PRIVATE)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, key())
            updateAAD(name.toByteArray(Charsets.UTF_8))
        }
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        if (prefs.edit().putString(name, Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)).commit()) "ok" else ""
    } catch (_: Exception) { "" }

    @JvmStatic @Synchronized fun read(name: String): String = try {
        val saved = requireNotNull(context).getSharedPreferences("ai_assistant_vault", Context.MODE_PRIVATE).getString(name, null)
        if (saved == null) "" else {
            val bytes = Base64.decode(saved, Base64.NO_WRAP)
            require(bytes.size >= 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                updateAAD(name.toByteArray(Charsets.UTF_8))
            }
            String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
        }
    } catch (_: Exception) { "" }

    @JvmStatic @Synchronized fun erase(name: String): String = try {
        if (requireNotNull(context).getSharedPreferences("ai_assistant_vault", Context.MODE_PRIVATE).edit().remove(name).commit()) "ok" else ""
    } catch (_: Exception) { "" }
}
