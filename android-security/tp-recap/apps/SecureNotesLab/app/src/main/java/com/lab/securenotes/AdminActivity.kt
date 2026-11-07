package com.lab.securenotes

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class AdminActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val vue = TextView(this)
        vue.setPadding(40, 300, 40, 40)
        vue.textSize = 18f
        vue.text = "Zone interne\n\nProjet confidentiel : ORION-DEMO"
        setContentView(vue)
    }
}
