package edu.lab.mobilevault

import android.util.Base64

/** Deliberately insecure educational placeholder. Base64 is NOT encryption. */
object VaultCrypto {
    fun protect(plain: String): String = Base64.encodeToString(plain.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
    fun unprotect(encoded: String): String = String(Base64.decode(encoded, Base64.NO_WRAP), Charsets.UTF_8)
}
