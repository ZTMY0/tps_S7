package com.fintrust.vault

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class LoginActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.setPadding(60, 160, 60, 40)

        val titre = TextView(this)
        titre.text = "FinTrustVault"
        titre.textSize = 24f
        layout.addView(titre)

        val champUser = EditText(this)
        champUser.hint = "Identifiant"
        layout.addView(champUser)

        val champPass = EditText(this)
        champPass.hint = "Mot de passe"
        champPass.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        layout.addView(champPass)

        val boutonLogin = Button(this)
        boutonLogin.text = "Se connecter"
        layout.addView(boutonLogin)

        boutonLogin.setOnClickListener {
            // Démo uniquement : n'importe quel couple non vide est accepté
            if (champUser.text.isNotBlank() && champPass.text.isNotBlank()) {
                Session.estConnecte = true
                startActivity(Intent(this, NotesListActivity::class.java))
                finish()
            } else {
                Toast.makeText(this, "Veuillez saisir un identifiant et un mot de passe", Toast.LENGTH_SHORT).show()
            }
        }

        setContentView(layout)
    }
}
