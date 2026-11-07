package com.lab.securenotes

object SyncManager {
    // La cle ne doit jamais etre en dur dans le code ni journalisee.
    // En production : recuperee depuis un stockage securise (Keystore / backend) au moment du besoin.
    fun lancerSynchronisation() {
        // Synchronisation effectuee sans exposer de secret dans les logs.
    }
}

