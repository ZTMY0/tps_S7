# Séance 1 — Note complémentaire (état final de `sqlnet.ora`)

Le rapport de la Séance 1 (PDF) décrit le `sqlnet.ora` du 16 septembre 2026. L'état final sur la VM (6 novembre 2026) diffère sur deux paramètres :

| Paramètre | Séance 1 | État final |
|---|---|---|
| `TCP.INVITED_NODES` | `(<VM_IP>,127.0.0.1)` | `(<VM_IP>,127.0.0.1,<ADMIN_CLIENT_IP>)` |
| `SQLNET.EXPIRE_TIME` | `30` | `10` |

Les autres paramètres sont inchangés. Le fichier réel ne contient pas `SQLNET.AUTHENTICATION_SERVICES`. Preuve : `evidence/logs/sqlnet.ora.live`.
