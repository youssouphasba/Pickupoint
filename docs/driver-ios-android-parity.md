# Parcours livreur : cohérence iOS / Android

## Corrections

- Acceptation : l’action appartient à l’écran des missions, pas à la carte retirée après l’acceptation. Actualisation du détail, des listes et du solde, sélection de « Mes missions » et ouverture du détail sans dépendre des animations. Une seule action d’acceptation/refus peut être en cours sur cet écran.
- Aperçu : la requête reste identique pendant les reconstructions de la feuille ; les boutons rendent une action à l’écran propriétaire.
- Détail : rechargement au retour au premier plan et lors des notifications. Une notification ouvrant directement une mission invalide aussi son détail en cache.
- Carte : une modification des coordonnées recrée la carte sur la destination actuelle. Après collecte, la navigation reste dirigée vers la livraison, y compris après un incident. Une latitude sans longitude ne provoque plus d’exception.
- Navigation : lien Google Maps adapté à chaque système, secours web après refus ou exception, erreur lisible si aucune ouverture n’aboutit. Waze utilise le même secours.
- Actualisation manuelle : les listes courtes, vides ou en erreur restent défilables pour permettre le geste de rafraîchissement.
- Notifications : écouteurs installés avant les demandes d’autorisation, initialisation unique et nettoyage des abonnements. Sur iOS, attente du jeton APNS avant FCM, tentatives limitées et nouvelle tentative au retour au premier plan.
- Premier plan : affichage local sur les deux systèmes et suppression de la présentation distante iOS pour éviter le doublon. Les offres sont masquées pour les livreurs occupés ou indisponibles. Cela ne remplace pas les contrôles serveur pour les notifications en arrière-plan.
- Activité iOS : synchronisation globale des missions du compte livreur, indépendante de l’accueil et de la vue client. Compte à rebours basé sur le délai serveur, puis chronomètre depuis l’acceptation après collecte ; arrêt lorsque la mission n’est plus active. Un délai expiré reste à zéro dans la vue native, sans repartir à la hausse.
- Preuve photo : annulation et erreurs de la caméra gérées ; aucun changement d’état après fermeture de l’écran pendant la prise de photo ou la compression.
- Localisation : la règle « Toujours » est commune aux livreurs iOS et Android ; les instructions de réglage respectent le système.
- Demande iOS : après le consentement du livreur et l’autorisation pendant l’utilisation, Denkma demande nativement le passage à « Toujours ». Les clients conservent leur demande pendant l’utilisation.

## Vérification

Les tests couvrent l’acceptation avec détail précédemment en cache et disparition de la carte, le rafraîchissement d’une liste vide, le retour depuis la navigation, les notifications de modification, les liens natifs et leur secours, le jeton APNS retardé, les alertes lorsque le livreur est occupé ou indisponible, et les arguments de l’activité iOS.

La vérification sur appareil reste nécessaire : ces tests simulent les plateformes Flutter, pas iOS ni Android eux-mêmes. Tester sur iPhone et Android l’acceptation depuis la liste et depuis une notification, la collecte, une nouvelle adresse/repli, la sortie vers Maps/Waze et le retour, la photo de preuve, ainsi que les notifications au premier plan, téléphone verrouillé et application relancée.

Les différences natives intentionnelles demeurent : motifs de vibration et notification persistante Android, Live Activity sur les iPhone compatibles, règles de suspension propres à chaque système.

## Passage natif à « Toujours » sur iPhone

Le canal dédié du livreur appelle `requestAlwaysAuthorization()` uniquement depuis une autorisation pendant l’utilisation. Il attend le premier plan, notamment après la fermeture de la première fenêtre de localisation. Les demandes simultanées sont regroupées. Une autorisation déjà complète ne provoque aucune nouvelle demande.

Le retour de la fenêtre système est traité même si le livreur choisit de conserver l’autorisation pendant l’utilisation : Apple ne transmet pas nécessairement de changement d’autorisation dans ce cas. Le choix observé est mémorisé pour ne pas relancer cette fenêtre après un refus. Si iOS ignore la demande, notamment après « Autoriser une fois », le contrôle retourne sans attendre indéfiniment et sans considérer la permission comme acquise. Une réinitialisation des autorisations permet une nouvelle tentative. [Demande d’autorisation Apple](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()), [changements d’autorisation](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanagerdidchangeauthorization(_:)).

Le mobile relit toujours l’autorisation effective. Si « Toujours » n’est pas obtenu, il propose les réglages puis vérifie de nouveau au retour. La disponibilité et l’acceptation restent bloquées sans cette autorisation. Une ancienne release sans le canal natif conserve le secours par les réglages ; un patch ne peut pas ajouter le pont Swift à cette release.

Le texte de la fenêtre explique que le suivi concerne les livreurs disponibles ou en livraison, y compris en arrière-plan et téléphone verrouillé. Il ne promet pas de suivi après un arrêt forcé de l’application. Aucun changement de permission Android ni nouvelle dépendance Flutter.

Le choix de la demande native est conservé uniquement dans les préférences de l’application, sans transmission au serveur. Le manifeste embarqué déclare l’usage de `UserDefaults` pour cette préférence avec la raison Apple `CA92.1`. Il ne remplace pas les déclarations de collecte de données et les fiches de confidentialité de l’application ou de ses SDK. [Raisons d’utilisation des API Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

### Vérification de la demande

Tests Flutter : accord natif, refus, permission réelle inchangée malgré une réponse positive, première demande, secours après erreur ou canal absent, concurrence, fermeture de l’écran pendant la demande et absence de demande « Toujours » pour les clients. Contrôles Python : canal, enregistrement, intégration Xcode et descriptions de localisation. Les tests XCTest de Runner couvrent le retour sans changement d’autorisation, l’appel ignoré, le premier plan et la remise à zéro des autorisations ; leur exécution nécessite Xcode.

Sur une nouvelle release iOS, vérifier :

1. Client : accepter l’accès pendant l’utilisation ; aucune demande de passage à « Toujours ».
2. Livreur : autoriser pendant l’utilisation puis accepter « Toujours » ; aucune ouverture des réglages nécessaire.
3. Livreur : conserver pendant l’utilisation ; aucune disponibilité ou acceptation possible, et réglages proposés.
4. Livreur : choisir « Autoriser une fois » ; aucun écran bloqué en attente d’une fenêtre ignorée par iOS.
5. Déjà autorisé ou refus précédent : aucun nouveau dialogue natif forcé ; les réglages restent accessibles.
6. Depuis les réglages, accorder ou retirer « Toujours », revenir et contrôler l’autorisation réellement obtenue.

## Écran verrouillé iOS

- iOS 16.1 minimum, y compris sur les iPhone sans Dynamic Island. La barre bleue indique la localisation en arrière-plan ; elle ne remplace pas l’activité de la mission.
- Le canal natif est enregistré auprès du registre des plugins Flutter. Les dates ISO UTC sont acceptées avec ou sans fraction de seconde. L’application et l’extension partagent le même contrat d’attributs, contrôlé par un test ; les champs supplémentaires sont optionnels pour décoder une activité de l’ancienne version pendant la mise à jour.
- Une activité existante est mise à jour, sans recréation à chaque changement de délai ou après collecte. Les créations en arrière-plan sont reportées jusqu’au retour au premier plan, conformément à ActivityKit. Une reprise resynchronise l’état natif, même après la disparition d’une activité.
- Les erreurs ne sont plus silencieuses : un message dans l’espace livreur distingue les autorisations désactivées, une version incompatible, une version de Denkma nécessitant une mise à jour et un échec temporaire. Le bouton de réglages ouvre les réglages de l’application ; le bouton de reprise permet une nouvelle tentative pour les erreurs temporaires.
- Si l’activité ne peut pas démarrer, une notification locale silencieuse donne la mission et l’heure limite de collecte, sous réserve des autorisations de notification iOS. Cette notification de secours n’est pas un compteur animé et ne peut pas contourner les préférences d’écran verrouillé ou de concentration du téléphone.
- Une erreur réseau lors de l’actualisation des missions ne ferme pas l’activité existante. La déconnexion ou le changement de compte ferme l’ancienne activité et son suivi local.
- Le widget utilise un rendu compact, avec couleurs explicites pour rester lisible en mode clair et sombre, et un lien vers le détail de la mission.
- La dépendance native de Runner vers l’extension est explicite. Codemagic vérifie dans l’IPA exporté la présence et l’exécutable de l’extension WidgetKit, son identifiant, ses versions et l’activation des Live Activities avant de publier les paramètres de mise à jour.

Ces corrections modifient le code Swift et le projet Xcode : une nouvelle release iOS est obligatoire, pas un simple patch Shorebird. Aucun asset ni dépendance Flutter n’a été ajouté. La compilation Xcode et le rendu réel sur appareil ne sont pas vérifiables depuis l’environnement Windows.

### Recette appareil avant diffusion

1. Installer la nouvelle release sur un iPhone SE et un iPhone avec Dynamic Island sous iOS compatible. Vérifier les autorisations « Activités en direct », les notifications sur l’écran verrouillé et les options d’accès lorsque l’appareil est verrouillé.
2. Accepter une course depuis la liste et depuis une notification ouvrant directement le détail ; verrouiller le téléphone. Vérifier la référence et le délai exact configuré côté serveur.
3. Confirmer la collecte : la même activité passe à « Livraison en cours », sans disparition ni deuxième paiement ou deuxième mission. Vérifier le chronomètre après ouverture de Maps/Waze et verrouillage.
4. Modifier le délai côté serveur et revenir dans l’application ; vérifier la mise à jour. À expiration, le compteur ne doit pas compter à la hausse.
5. Terminer, annuler ou faire réattribuer la mission, puis actualiser l’état dans Denkma ; l’activité et la notification de secours doivent disparaître.
6. Désactiver les Live Activities, vérifier le message et la notification de secours, réactiver dans les réglages et revenir dans Denkma. Vérifier la récupération et l’absence de doublon.
7. Vérifier avec réseau dégradé, changement de compte, texte agrandi et modes clair/sombre.

Le compteur SwiftUI est animé par iOS même si Dart est suspendu. En revanche, les changements de mission ne sont propagés que lorsque l’application reçoit et traite un nouvel état. Aucune infrastructure de push ActivityKit n’a été ajoutée : un arrêt serveur immédiat lorsque l’application est arrêtée de force n’est pas garanti. ActivityKit applique aussi ses limites système de durée et d’affichage.
