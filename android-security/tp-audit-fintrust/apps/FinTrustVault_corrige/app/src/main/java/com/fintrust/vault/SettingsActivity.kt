package com.fintrust.vault

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val vue = TextView(this)
        vue.setPadding(40, 80, 40, 40)
        vue.textSize = 16f
        vue.text = "Paramètres du compte\n\nJeton de session actif : ${Session.token}"
        setContentView(vue)
    }
}
