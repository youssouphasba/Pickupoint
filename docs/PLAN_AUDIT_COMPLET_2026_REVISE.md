# PLAN AUDIT COMPLET 2026 - VERSION RELUE
> Relecture technique du 2026-03-18
> Objectif : separer les vrais risques encore ouverts, les points deja corriges, et ceux a reclasser.

---

## Resume

| Verdict | Nombre | Sens |
|---|---:|---|
| `confirme` | 25 | Risque legitime encore ouvert dans le code actuel |
| `deja_corrige` | 4 | Le plan original n'est plus a jour sur ce point |
| `a_reclasser` | 5 | Le risque existe faiblement, est mal formule, ou la priorite est trop haute |
| **Total** | **34** | |

---

## Tri des points

| ID | Verdict | Note rapide |
|---|---|---|
| C1 | `confirme` | Secrets presents localement et a rotater. En revanche, je n'ai pas trouve de preuve qu'ils aient deja ete commits dans l'historique git. |
| C2 | `confirme` | Les fichiers Firebase admin sont sensibles et doivent rester hors git. Ne pas melanger ce cas avec `google-services.json`, qui n'est pas du meme niveau de sensibilite. |
| C3 | `deja_corrige` | Le demarrage bloque deja en production si `JWT_SECRET` est faible ou par defaut. |
| C4 | `deja_corrige` | Le demarrage bloque deja en production si `OTP_PROVIDER=mock`. Le vrai reliquat est surtout du nettoyage de code mort autour de `test_code`. |
| C5 | `confirme` | Le HTML de tracking injecte encore des valeurs dynamiques sans echappement. |
| C6 | `confirme` | Le HTML de confirmation injecte encore des valeurs dynamiques sans echappement. |
| H1 | `confirme` | La comparaison du secret webhook doit passer par `hmac.compare_digest`. |
| H2 | `confirme` | Le webhook manque d'idempotence atomique. Le vrai risque est double traitement paiement/event, pas un "double credit wallet" direct dans ce fichier. |
| H3 | `deja_corrige` | Le CORS debug est deja borne a des origines localhost explicites. |
| H4 | `confirme` | `/uploads` est servi publiquement, ce qui expose potentiellement avatars, KYC et notes vocales. |
| H5 | `confirme` | Les codes a 4 chiffres restent faibles sans rate limiting ni lockout. |
| H6 | `a_reclasser` | `token_urlsafe(12)` n'est pas faible en pratique. C'est du hardening utile, mais pas une urgence haute priorite. |
| H7 | `confirme` | Le suffixe telephone est injecte dans une regex sans `re.escape()`. |
| H8 | `confirme` | L'approbation de payout decremente `pending` sans garde atomique sur le solde bloque. |
| H9 | `deja_corrige` | `otp_service.py` ne renvoie plus `test_code`. Le reliquat est un champ mort encore renvoye par `request_otp`, mais il est vide dans le flux actuel. |
| M1 | `confirme` | Les operations wallet restent multi-etapes sans transaction. |
| M2 | `confirme` | Les transitions colis/missions restent sequentielles et non atomiques. |
| M3 | `confirme` | Les coordonnees GPS dans `confirm.py` ne sont pas bornees par schema. |
| M4 | `confirme` | L'upload avatar n'a ni limite de taille ni validation binaire fiable. |
| M5 | `confirme` | Plusieurs endpoints sensibles n'ont pas encore de rate limiting explicite. |
| M6 | `confirme` | Plusieurs champs texte n'ont pas de `max_length`, ce qui ouvre la porte a des payloads trop gros. |
| M7 | `confirme` | `user_sessions.expires_at` existe sans index TTL. |
| M8 | `confirme` | Pas de revocation anticipee des access tokens. C'est legitime, meme si c'est plus produit/securite qu'incident critique. |
| M9 | `a_reclasser` | C'est un vrai sujet de validation metier, mais pas une "injection MongoDB" credible dans l'etat actuel. |
| M10 | `confirme` | La normalisation telephone backend est encore incoherente selon les flux. |
| M11 | `confirme` | L'identification destinataire par suffixe de telephone est fragile et collision-prone. |
| M12 | `confirme` | La validation upload basee sur le header `Content-Type` reste insuffisante. |
| L1 | `confirme` | Les security headers HTTP manquent encore. |
| L2 | `confirme` | Le webhook loggue encore le payload complet. |
| L3 | `confirme` | Le `Dockerfile` fait `COPY . .` sans `.dockerignore` dedie. |
| L4 | `a_reclasser` | Sujet utile, mais c'est de la maturite plateforme, pas un correctif prioritaire de ce lot. |
| L5 | `confirme` | Le job d'auto-release peut encore relacher une mission a la limite temporelle. |
| L6 | `a_reclasser` | Le risque d'enumeration du tracking est surevalue vu l'espace de codes actuel et le rate limiting deja pose. |
| L7 | `a_reclasser` | Le parsing `tx_ref` est un peu fragile, mais `parcel_id` actuel est genere sans tirets. C'est du durcissement, pas un bug urgent. |

---

## Ordre d'execution revise

### P0 - a traiter avant toute exposition reelle

1. `C1` - Rotater les secrets reels encore presents en local ou en env.
2. `C2` - Retirer les credentials Firebase admin du disque de travail partage et verrouiller les patterns git.
3. `C5` + `C6` - Echappement HTML dans les pages publiques.
4. `H1` + `H2` - Rendre le webhook compare-digest + idempotent/atomique.
5. `H4` - Arreter d'exposer les fichiers sensibles via `/uploads`.

### P1 - haute priorite avant mise en production

1. `H5` - Renforcer `delivery_code` et `relay_pin`.
2. `H7` - Echappement regex sur recherche telephone.
3. `H8` - Garde atomique sur approbation payout.
4. `M3` - Validation stricte des coordonnees GPS.
5. `M4` + `M12` - Validation taille + magic bytes des uploads.
6. `M5` - Rate limiting des endpoints sensibles.
7. `M7` - TTL index sur `user_sessions`.
8. `M10` + `M11` - Normalisation telephone et suppression du matching par suffixe.

### P2 - robustesse post-lancement

1. `M1` + `M2` - Transactions Mongo sur wallet et transitions critiques.
2. `M6` - Limites de taille sur champs texte.
3. `M8` - Revocation / blacklist des tokens.
4. `L1` - Security headers HTTP.
5. `L2` - Sanitiser les logs webhook.
6. `L3` - Ajouter un `.dockerignore`.
7. `L5` - Durcir le job d'auto-release.

### P3 - hardening et hygiene

1. `H6` - Allonger les confirm tokens si souhaite.
2. `M9` - Typer `status` cote admin.
3. `L4` - Strategie de rotation des secrets.
4. `L6` - Reevaluer si CAPTCHA utile sur tracking public.
5. `L7` - Nettoyer le format de `tx_ref` a l'occasion.

---

## Notes importantes

- Le plan original surestimait plusieurs points deja couverts par la configuration actuelle.
- `C3`, `C4` et `H3` ne doivent plus bloquer le lot.
- `H9` n'est plus un incident actif ; c'est surtout un nettoyage de contrat API.
- `C1` et `C2` restent prioritaires meme sans preuve de commit git : un secret reel present sur disque ou dans une env partagee doit etre considere compromis.
- `google-services.json` ne doit pas etre traite automatiquement comme un service account admin. Le cas sensible, c'est surtout le JSON Firebase Admin SDK.

---

## References code verifiees

- `backend/config.py`
- `backend/main.py`
- `backend/routers/auth.py`
- `backend/routers/confirm.py`
- `backend/routers/tracking.py`
- `backend/routers/webhooks.py`
- `backend/routers/admin.py`
- `backend/routers/parcels.py`
- `backend/routers/users.py`
- `backend/database.py`
- `backend/services/parcel_service.py`
- `backend/services/otp_service.py`
- `backend/services/wallet_service.py`
