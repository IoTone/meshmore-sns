package com.iotone.meshmore_sns_app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM under a key the Android Keystore generates and will not export.
 *
 * The Dart side never sees key material: it hands over plaintext and gets back
 * a sealed blob (12-byte IV followed by ciphertext and tag). A copy of the
 * sealed file is therefore unreadable on another device, which is why the
 * history store is excluded from Auto Backup and device transfer rather than
 * merely encrypted.
 *
 * A key can be invalidated by the platform (a lock-screen change on older
 * releases, or a restore of this app's data onto another device). That
 * surfaces as a decrypt failure, which the Dart side treats as a corrupt store
 * and reports once instead of overwriting.
 */
object SecureStore {
    private const val ALIAS = "meshmore_history_key"
    private const val PROVIDER = "AndroidKeyStore"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                // Bound to the device, not to a screen-lock secret: the app
                // reads history before the user unlocks, and a boot into the
                // locked state must not lose the store.
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    fun seal(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val body = cipher.doFinal(plain)
        return cipher.iv + body
    }

    fun open(sealed: ByteArray): ByteArray {
        require(sealed.size > IV_BYTES) { "shorter than an IV" }
        val iv = sealed.copyOfRange(0, IV_BYTES)
        val body = sealed.copyOfRange(IV_BYTES, sealed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
        return cipher.doFinal(body)
    }
}
