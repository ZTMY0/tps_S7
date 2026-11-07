package com.lab.securenotes

import android.content.Context

object Session {
    var estConnecte: Boolean = false

    // FIXED (attaque 4) : plus aucun secret dans le binaire.
    // La valeur serait obtenue du serveur apres authentification (simule).
    fun cleApi(): String = "valeur-obtenue-dynamiquement"

    // Jeton fictif, demonstration uniquement (genere a l'execution, pas une constante de cle)
    val token: String = listOf("demo", "token", "7A91").joinToString("_")

    // FIXED (attaque 5) : chiffre avec une cle de l'Android Keystore
    fun enregistrerTokenChiffre(context: Context) {
        val chiffre = ChiffrementKeystore.chiffrer(token)
        val prefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString("token", chiffre).apply()
    }
}
