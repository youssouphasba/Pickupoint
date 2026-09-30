# Protection des pièces d’identité et permis

## Protections applicatives

- Les dossiers privés ne peuvent pas être servis par `/uploads`, y compris avec des chemins normalisés ou détournés.
- Les documents se téléchargent uniquement depuis l’API authentifiée. Un utilisateur ne voit que ses pièces. Un superadmin peut les vérifier ; un admin doit recevoir l’habilitation `kyc_access_enabled`.
- Dans l’admin web, ouvrir **Utilisateurs → administrateur concerné → Accès aux pièces d’identité** pour accorder ou retirer cette habilitation. Seul un superadmin peut la modifier.
- Consultation, refus d’accès, téléversement, remplacement et changement d’habilitation sont visibles dans **Journal des actions**, avec acteur, date, type de document et compte concerné. Aucun contenu de pièce ni jeton n’est journalisé.
- Les réponses privées utilisent `Cache-Control: private, no-store`. Les aperçus web sont fermés à la déconnexion de la fenêtre qui les a ouverts. Une copie déjà enregistrée ou une photo d’écran ne peut pas être effacée à distance.
- Dans l’aperçu admin mobile, l’image est masquée lorsque l’application passe en arrière-plan et retirée du cache d’images à la fermeture. Le document n’est pas enregistré sur disque par cet aperçu. Cela ne remplace pas un mécanisme natif de blocage des captures d’écran.
- Les liens externes sont refusés pour les pièces. Le mobile ne joint son jeton qu’à l’origine exacte de l’API et ne suit pas les redirections authentifiées.
- Les photos sont réellement décodées puis reconstruites en JPEG sans métadonnées. Taille, résolution et formats sont contrôlés. Les PDF nécessitent un verdict antivirus avant stockage ; sans antivirus disponible, leur téléversement est refusé. L’application peut continuer à envoyer des photos.
- Le remplacement utilise un contrôle de concurrence puis supprime la version précédente. Le nettoyage programmé supprime les fichiers GridFS qui ne sont plus référencés, après `KYC_ORPHAN_GRACE_HOURS` (24 heures par défaut). Cette tâche n’est pas exécutée pendant les tests.

## Activation du chiffrement

Définir `KYC_ENCRYPTION_KEYS` dans les secrets du serveur : une clé Fernet aléatoire, URL-safe Base64 de 32 octets. Ne pas utiliser `JWT_SECRET` et ne jamais mettre cette clé dans Git, le frontend ou un log. Conserver une sauvegarde séparée et protégée de la clé : la perdre rend les pièces chiffrées illisibles.

Après configuration, les nouveaux téléversements sont chiffrés avant GridFS. Activer ensuite `KYC_REQUIRE_ENCRYPTION=true` pour refuser les téléversements si le chiffrement n’est pas disponible. Sans clé configurée, ce renforcement n’est pas actif ; la base ne doit donc pas être présentée comme intégralement chiffrée par l’application.

Pour les fichiers existants, depuis `backend`, sur le serveur disposant de la clé :

```text
python scripts/secure_kyc_documents.py
python scripts/secure_kyc_documents.py --apply
```

La première commande est une simulation sans écriture en base ni suppression. La seconde remplace les fichiers après mise à jour atomique de leur référence et retire l’ancienne copie. Vérifier les sauvegardes et la simulation avant de lancer `--apply`. Les résultats indiquent seulement des compteurs, jamais les pièces ni leurs chemins.

Pour changer de clé, placer la nouvelle clé en premier dans la liste `KYC_ENCRYPTION_KEYS`, séparée par des virgules, et garder les anciennes pour lire les documents existants. Exécuter la simulation avec `--rotate`, puis `--apply --rotate`. Ne retirer une ancienne clé qu’après migration vérifiée, y compris pour les sauvegardes conservées.

Les sauvegardes de la base et le chiffrement des volumes doivent également être configurés chez l’hébergeur. Cette vérification n’est pas possible depuis le dépôt.

## Activation de l’antivirus

Configurer un service ClamAV privé, inaccessible depuis Internet, puis renseigner `KYC_CLAMAV_HOST`, `KYC_CLAMAV_PORT` et éventuellement `KYC_CLAMAV_TIMEOUT_SECONDS`. Le backend utilise le protocole `INSTREAM` ; il refuse le document si ClamAV détecte une menace ou ne répond pas. Garder les signatures antivirus à jour et régler sa limite de flux au moins à `KYC_MAX_UPLOAD_BYTES`.

Activer `KYC_REQUIRE_ANTIVIRUS=true` une fois le service testé, pour imposer ce contrôle aussi aux photos. Sans service configuré, les photos sont reconstruites mais ne bénéficient pas d’un verdict antivirus. Ne pas transmettre ces pièces à un scanner public.

## Double authentification admin web

Configurer `ADMIN_MFA_TOTP_SECRETS` dans les secrets du serveur : objet JSON associant chaque email admin à sa clé Base32 aléatoire de 20 octets minimum. Chaque personne doit enregistrer sa propre clé dans une application d’authentification, par un canal privé, jamais dans une communication publique.

Pour un compte configuré, la connexion web demande d’abord le mot de passe, puis le code à six chiffres. Un code accepté ne peut pas être réutilisé ; les échecs répétés verrouillent temporairement cette étape. Les anciens cookies sans second facteur sont refusés dès activation sur le compte.

Un changement de clé invalide aussi les sessions web créées avec l’ancienne clé. En production, le cookie reste `Secure` même si le mode debug a été activé par erreur.

Après avoir configuré tous les administrateurs et testé une connexion, activer `ADMIN_REQUIRE_MFA=true`. Un compte sans clé n’a alors plus accès au dashboard. Ne pas activer ce paramètre avant l’enrôlement et une procédure de récupération conservée hors plateforme. Cette configuration concerne la connexion admin web ; elle ne transforme pas le PIN mobile en double authentification.

## Déploiement

Ces changements nécessitent le déploiement du backend et de l’admin web, puis la diffusion des modifications Dart du mobile. Aucun numéro de version, fichier natif ou dépendance mobile n’est modifié par ce travail. Aucun service payant, migration ou configuration de production n’est lancé automatiquement.

Références techniques : [Fernet et rotation des clés](https://cryptography.io/en/latest/fernet/), [PyOTP](https://pyauth.github.io/pyotp/), [protocole ClamAV INSTREAM](https://github.com/Cisco-Talos/clamav/blob/main/docs/man/clamd.8.in).
