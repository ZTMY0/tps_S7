package com.lab.securenotes

import android.content.Context

object Session {
    var estConnecte: Boolean = false

    // VULNERABLE (attaque 4) : secret code en dur (valeur fictive)
    const val API_KEY = "DEMO-KEY-12345"

    // Jeton fictif, demonstration uniquement
    val token: String = "demo_token_7A91"

    // VULNERABLE (attaque 5) : stockage en clair
    fun enregistrerToken(context: Context) {
        val prefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString("token", token).apply()
    }

    // Utilise pour que la constante soit bien conservee dans le binaire
    fun cleApi(): String = API_KEY
}
