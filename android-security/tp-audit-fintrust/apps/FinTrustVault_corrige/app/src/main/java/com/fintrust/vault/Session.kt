package com.fintrust.vault

object Session {
    // Jeton fictif, uniquement pour la démonstration de ce TP
    var token: String = "demo-token-${(1000..9999).random()}"
    var estConnecte: Boolean = false
}
