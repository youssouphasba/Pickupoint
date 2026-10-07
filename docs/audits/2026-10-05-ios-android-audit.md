# Audit iOS / Android — 5 octobre 2026

## Conclusion

L'application présente encore des défauts dans les transitions : passage en arrière-plan, démarrage depuis une notification, changement de session et reprise après une erreur réseau. Les parcours nominaux et leurs tests ne suffisent pas à détecter ces cas.

Six défauts distincts ont été reproduits par neuf tests de diagnostic. Six autres points sont établis par lecture des chemins de code et, lorsque nécessaire, des contrats des plateformes ; leur manifestation sur appareil reste à vérifier.

Cet audit porte sur l'état local du dépôt, y compris les modifications iOS/Android déjà présentes et non commitées. Il ne certifie ni le binaire installé sur les téléphones ni la version actuellement déployée du backend. Aucun correctif applicatif, commit, push ou déploiement n'a été effectué pendant cet audit. Seuls ce rapport et des tests de diagnostic isolés ont été ajoutés.

## Vérifications exécutées

| Vérification | Résultat |
| --- | --- |
| Suite mobile existante : `flutter test --no-pub` | 267 tests réussis |
| Régressions backend isolées : `python -m tests.run_regressions` | 438 tests réussis |
| Contrôles Live Activity / sources de patch : `python -m unittest scripts.test_ios_live_activity scripts.test_patch_source` | 17 tests réussis |
| Analyse statique mobile : `flutter analyze --no-pub` | Aucun problème signalé |
| Nouveaux diagnostics ciblés | 9 échecs sur les assertions fonctionnelles attendues, correspondant aux 6 défauts A01–A06 |

Les 722 contrôles existants réussis ne contredisent pas les nouveaux diagnostics : ceux-ci exercent d'autres enchaînements. Les tests backend utilisent des substituts pour les services externes ; aucun paiement réel ni envoi réel de notification n'a été déclenché.

Les neuf diagnostics sont conservés hors du dossier de tests mobile habituel, afin de ne pas modifier silencieusement la suite courante. Ils décrivent le comportement correct attendu et échouent actuellement ; ils devront être intégrés à la suite de régression avec leurs corrections.

Depuis le dossier `mobile`, les reproduire avec :

```powershell
flutter test --no-pub audit/test/mobile_diagnostics_2026_10_05_test.dart --reporter expanded
```

[Tests de diagnostic](C:/Users/Utilisateur/Pickupoint/mobile/audit/test/mobile_diagnostics_2026_10_05_test.dart)

Priorités : P1 = correction prioritaire avant de considérer ces flux fiables ; P2 = flux incomplet à corriger, avec un contournement possible.

## Défauts reproduits

### A01 — P1 — Une réponse tardive peut rétablir l'ancien compte

Plateformes : iOS et Android.

`fetchMe()` et le renouvellement des jetons mémorisent la session avant la requête, puis réécrivent l'état et le stockage après la réponse, sans vérifier que cette session est toujours la session courante.

Scénario : une requête du compte A est en cours, l'utilisateur passe au compte B, puis la réponse A arrive. Les deux diagnostics, profil et renouvellement de jetons, constatent le retour de l'identifiant A alors que B doit rester connecté. La même absence de garde concerne une déconnexion survenant pendant la requête.

Conséquences : ancien profil ou rôle réaffiché, jetons et données locales pouvant être réécrits avec ceux de l'ancienne session. Ce constat n'implique pas un accès à un compte arbitraire : il concerne les sessions successives de l'appareil.

Correction attendue : identifier chaque session par une génération ; refuser toute réponse et écriture de stockage appartenant à une génération périmée ; invalider les opérations en cours lors d'une déconnexion ou d'un changement de compte.

Sources : [chargement du profil](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/auth/auth_provider.dart:143), [renouvellement](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/auth/auth_provider.dart:396).

### A02 — P1 — Le suivi GPS peut s'arrêter lors d'une affectation en arrière-plan

Plateformes : iOS et Android.

Un changement de mission provoque l'arrêt de l'abonnement GPS. Son redémarrage est ensuite conditionné au premier plan.

Scénario reproduit : livreur disponible avec GPS actif → application en arrière-plan → réception de la nouvelle mission. Le nombre d'abonnements actifs passe de 1 à 0 et reste à 0. Cela peut notamment arriver si le livreur verrouille le téléphone pendant la réponse à l'acceptation.

Conséquence : trou dans la trace et dans les positions visibles par les personnes autorisées, jusqu'à une reprise du suivi.

Correction attendue : dissocier la durée de vie du flux GPS de l'identifiant de mission ; conserver le flux autorisé pendant le changement de destination des points, sans contourner les restrictions de l'OS.

Source : [réconciliation du suivi](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/location/driver_presence_service.dart:215).

### A03 — P1 — Une photo non envoyée peut conduire à créer un deuxième colis

Plateformes : iOS et Android, parcours client.

La confirmation crée d'abord le colis, puis téléverse sa photo. Si le téléversement échoue, l'écran affiche une erreur générale et permet de confirmer de nouveau sans conserver l'identifiant créé.

Le diagnostic reproduit deux créations après deux appuis, avec une seule intention d'envoi. La première création peut déjà avoir déclenché les traitements associés. Aucun double débit réel n'a été reproduit : le défaut prouvé est la duplication de création.

Correction attendue : rendre la création idempotente avec une référence d'opération ; conserver le colis créé ; proposer de reprendre uniquement la photo et afficher explicitement l'état partiellement réussi.

Sources : [confirmation et photo](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/client/screens/quote_screen.dart:95), [création serveur](C:/Users/Utilisateur/Pickupoint/backend/services/parcel_service.py).

### A04 — P2 — Le clic sur une notification locale n'est pas récupéré au démarrage

Plateformes : iOS et Android.

L'application traite les notifications FCM initiales et les clics locaux lorsque le gestionnaire est actif, mais ne consulte pas les informations de lancement des notifications locales. Les deux diagnostics fournissent un clic de lancement et constatent que ces informations ne sont jamais lues.

Conséquence : un clic sur un minuteur Android ou une notification locale de repli iOS peut lancer l'application sans ouvrir la bonne mission lorsque le processus n'était plus actif. Cela ne concerne pas indistinctement toutes les notifications FCM.

Correction attendue : récupérer `getNotificationAppLaunchDetails()`, conserver la destination jusqu'à la restauration de session et éviter de traiter deux fois un même lancement.

Source : [initialisation et navigation](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/notifications/notification_service.dart:656). Le traitement distinct du lancement est documenté par [flutter_local_notifications](https://pub.dev/documentation/flutter_local_notifications/latest/).

### A05 — P2 — Le lien d'une mission peut être perdu pendant la restauration de connexion

Plateformes : routeur partagé, particulièrement visible avec une Live Activity iOS.

Le routeur reconnaît `AuthStatus.unknown`, mais pas l'état Riverpod `AsyncLoading` initial. Dans ce dernier cas, il considère l'utilisateur comme déconnecté et remplace le lien de mission par la page de connexion.

Le diagnostic utilisant le routeur réel constate `/auth/phone` au lieu de `/driver/mission/active` pendant le chargement de session. La conservation spéciale des retours de paiement ne protège pas ce parcours.

Correction attendue : distinguer session en chargement et session déconnectée ; conserver une destination validée pendant toute la restauration ou la connexion, puis appliquer les autorisations du compte.

Sources : [redirection d'authentification](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/router/app_router.dart:329), [lien de la Live Activity](C:/Users/Utilisateur/Pickupoint/mobile/ios/DenkmaLiveActivity/DenkmaLiveActivity.swift).

### A06 — P2 — Une Live Activity différée ne déclenche aucun repli

Plateforme : iOS.

Si la mission arrive lorsque l'application est déjà en arrière-plan et qu'aucune activité correspondante n'existe, le pont natif renvoie `deferred`. Le code Dart efface alors l'avertissement et sort avant l'envoi de la notification de repli.

Le diagnostic reproduit cette réponse native et constate l'absence de notification de repli. Le livreur peut donc ne voir ni activité ni notification de mission jusqu'à la réouverture de l'application.

Correction attendue : conserver l'état différé, afficher le repli lorsque les notifications sont autorisées, puis retenter à la reprise. Une notification de repli doit annoncer l'échéance, sans être présentée comme un véritable minuteur dynamique.

Sources : [report natif](C:/Users/Utilisateur/Pickupoint/mobile/ios/Runner/DenkmaLiveActivityBridge.swift:84), [sortie prématurée](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/notifications/notification_service.dart:542). La contrainte de démarrage n'est pas à contourner : voir [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Autres incohérences et flux incomplets relevés dans le code

Ces constats sont fondés sur les branches de code et les contrats des plugins. Ils n'ont pas fait l'objet d'une reproduction sur un téléphone physique pendant cet audit.

### A07 — P1 — Nettoyage incomplet des ressources d'appel WhatsApp

Plateformes : iOS et Android, livreur.

Le microphone et la connexion WebRTC sont créés dans des variables locales. Ils ne sont transférés aux champs nettoyés par le gestionnaire d'erreur qu'après la réussite de plusieurs opérations réseau. Une exception avant ce transfert laisse le nettoyage sans référence aux ressources créées. La sortie de l'écran pendant ces opérations présente également un risque de ressources conservées.

De plus, l'interrogation de l'état de l'appel s'arrête après 20 tentatives espacées de deux secondes, sans clôture associée : les événements tardifs peuvent ne plus être traités par ce suivi.

Correction attendue : propriété explicite des ressources dès leur création, fermeture dans tous les chemins d'échec et d'abandon, suivi cohérent jusqu'à la fin réelle de l'appel. Vérifier sur appareil que le microphone est libéré après un échec réseau. Aucun enregistrement ou transfert audio non autorisé n'a été démontré.

Source : [création audio et gestion d'erreur](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/driver/screens/mission_detail_screen.dart:735).

### A08 — P2 — Des appels téléphoniques clients peuvent être refusés à tort

Plateformes : iOS et Android selon la version et la configuration de l'appareil.

Les boutons d'appel du relais et du livreur vérifient `canLaunchUrl(tel:...)` avant d'ouvrir le téléphone. Les déclarations de visibilité attendues pour cette vérification ne sont pas présentes pour `tel` dans les configurations natives consultées. Le parcours livreur, lui, tente directement l'ouverture.

Correction attendue : tenter l'ouverture avec gestion explicite du résultat et de l'exception, ou compléter les déclarations natives nécessaires. Un changement du manifeste ou du plist exige une release native.

Source : [appels depuis le détail client](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/client/screens/parcel_detail_screen.dart:1787). Le plugin précise les limites de cette vérification dans [url_launcher](https://pub.dev/packages/url_launcher).

### A09 — P2 — Activation et récupération des permissions de notification inégales selon le rôle

Sur Android récent, l'initialisation ne demande pas elle-même l'autorisation. Le bandeau d'activation est placé sur les accueils client et livreur, mais pas relais. Un relais arrivant directement dans son espace après une installation peut manquer la proposition d'activation.

Sur iOS, le bandeau réexécute simplement la demande après un refus, sans proposer les réglages système comme le fait déjà l'écran de paramètres. Le rafraîchissement de l'état à la reprise n'est pas uniformisé entre ces interfaces.

Correction attendue : un parcours commun à tous les rôles, distinction entre première demande et refus, accès aux réglages quand nécessaire, relecture de l'autorisation au retour. L'accès manuel aux paramètres existe : il ne s'agit pas d'un blocage irréversible.

Sources : [bandeau partagé](C:/Users/Utilisateur/Pickupoint/mobile/lib/shared/notifications/notification_permission_banner.dart), [service](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/notifications/notification_service.dart:106). Voir le comportement d'installation sur [Android 13 et suivants](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

### A10 — P2 — La Live Activity n'a pas de mise à jour distante autonome

Plateforme : iOS ; vérifier aussi la fraîcheur du minuteur local Android.

Le pont crée l'activité avec `pushType: nil` et ne met pas en place de jeton ActivityKit destiné au serveur. Le gestionnaire de messages en arrière-plan ne synchronise pas son état natif. Une annulation, une réaffectation ou un changement de délai côté admin n'a donc pas de canal ActivityKit autonome pour actualiser l'écran verrouillé lorsque l'application est suspendue ou arrêtée.

La reprise de l'application peut resynchroniser l'affichage ; elle ne garantit pas sa fraîcheur entre-temps. Cette limite était déjà mentionnée dans la documentation de parité et reste un flux incomplet.

Correction attendue : définir la fraîcheur exigée, les états d'expiration et de clôture ; si la synchronisation hors processus est requise, implémenter le canal ActivityKit serveur avec association sécurisée des jetons et gestion de leur cycle de vie. Un push FCM générique ne constitue pas à lui seul cette implémentation.

Sources : [création de l'activité](C:/Users/Utilisateur/Pickupoint/mobile/ios/Runner/DenkmaLiveActivityBridge.swift:98), [gestionnaire de fond](C:/Users/Utilisateur/Pickupoint/mobile/lib/main.dart:27), [limites connues](C:/Users/Utilisateur/Pickupoint/docs/driver-ios-android-parity.md).

### A11 — P2 — L'échec de prise de photo n'est pas traité côté client

Plateformes : iOS et Android.

`_takeParcelPhoto()` ne gère pas l'exception du sélecteur/caméra et ne vérifie pas `mounted` après l'attente. Un refus d'accès ou une sortie de page pendant la capture n'a donc pas de traitement complet, contrairement au parcours photo livreur déjà renforcé.

Correction attendue : traiter refus, annulation et indisponibilité séparément ; proposer les réglages si nécessaire ; ne pas modifier un écran détruit.

Source : [prise de photo client](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/client/screens/create_parcel_screen.dart:361).

### A12 — P2 — La nouvelle version peut être annoncée avant sa disponibilité sur le store

Plateformes : iOS et Android ; constat conditionnel à l'activation de la synchronisation CI.

Le workflow synchronise la dernière version dans les paramètres backend après la construction et avant la disponibilité publique vérifiée dans le store. Si `APP_UPDATE_ADMIN_BASE_URL` est configuré, l'application peut annoncer une version que l'utilisateur ne peut pas encore télécharger, notamment pendant la validation Apple.

Le script conserve les versions minimales existantes : ce point ne prouve pas un blocage forcé de tous les utilisateurs.

Correction attendue : distinguer version construite et version réellement publiée ; annoncer cette dernière seulement après vérification du canal de distribution concerné.

Sources : [workflow iOS](C:/Users/Utilisateur/Pickupoint/codemagic.yaml:310), [synchronisation des paramètres](C:/Users/Utilisateur/Pickupoint/scripts/sync_app_update_settings.py:101).

## Ordre de correction recommandé

1. Sécuriser les sessions, maintenir le suivi GPS et rendre la création de colis idempotente : A01–A03.
2. Fermer systématiquement les ressources d'appel : A07.
3. Unifier la reprise depuis les notifications et les liens ; couvrir la Live Activity différée : A04–A06.
4. Finaliser permissions, appels téléphoniques et capture de photo : A08, A09, A11.
5. Compléter la synchronisation distante de l'écran verrouillé et fiabiliser l'annonce des versions : A10, A12.

Pour chaque correction, faire passer le diagnostic correspondant puis la suite existante, sans introduire de dérogation globale aux permissions ou aux contrôles d'accès.

## Validation sur appareils encore indispensable

Le poste d'audit Windows ne permet pas de compiler avec Xcode ni de certifier le rendu de l'écran verrouillé. Les contrôles Python sur les fichiers iOS ne sont pas une compilation native.

La recette doit couvrir au minimum un iPhone SE 2022 et un Android récent, puis les versions minimales officiellement supportées :

- Accepter une mission sur réseau lent, verrouiller avant la réponse, vérifier suivi GPS et affichage de l'échéance.
- Ouvrir la mission depuis une notification et une Live Activity : application ouverte, en arrière-plan, puis processus arrêté.
- Annuler/réaffecter la mission ou modifier son délai côté admin pendant que le téléphone est verrouillé.
- Refuser puis réautoriser position, notifications, caméra et microphone ; vérifier chaque rôle, dont le relais.
- Changer de compte ou se déconnecter pendant un chargement et un renouvellement de jeton.
- Couper le réseau après création du colis et avant envoi de photo ; reprendre sans deuxième colis.
- Faire échouer un appel puis quitter l'écran ; contrôler l'arrêt du microphone et la fin du suivi d'appel.
- Tester Maps/Waze puis retour dans Denkma, GPS temporairement indisponible, reprise réseau et batterie restreinte.

Une notification persistante Android et une Live Activity iOS sont deux mécanismes différents. L'objectif doit être la cohérence de l'information, des permissions et des actions, pas une identité artificielle du comportement des deux OS. Aucun audit ni ensemble de tests ne permet de promettre « plus aucun bug ».
