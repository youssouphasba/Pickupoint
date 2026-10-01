# Audit Denkma — 1er octobre 2026

Ce document décrit le constat initial, avant corrections. Le travail réalisé ensuite et ses limites de validation sont consignés dans [le bilan des corrections](2026-10-01-corrections.md).

## Conclusion

Le code comporte encore des défauts financiers, de contrôle des accès et de cohérence des missions. Les tests existants passent, mais des scénarios complémentaires reproduisent des cas qu'ils ne couvrent pas.

19 défauts applicatifs sont documentés ci-dessous : 18 reproduits sur des données synthétiques et 1 établi par lecture croisée backend/mobile, sans essai sur téléphone. S'ajoutent une alerte sur les dépendances web, un écart de couverture du parcours GPS et les problèmes de lisibilité de « Solde et revenus » signalés pendant l'audit.

Les trois priorités bloquantes sont la création de solde par répétition acceptation/libération, l'exposition des codes de remise et le contournement de la vérification du PIN au relais.

Cet audit ne prouve ni une exploitation ni une fuite en production. Aucun correctif applicatif, aucune migration, aucun paiement et aucune modification de données réelles n'ont été effectués.

## Périmètre et méthode

Base examinée : branche `master`, commit `3696a40063f915ff9aefbbf3b0ffb23ec07770ac` ; version mobile `1.0.28+48`.

Lecture ciblée des routes et services backend, modèles de données, autorisations, paiements, commissions, retraits, transitions de livraison, dispatch, notifications, GPS, documents privés, fidélité, parrainage, promotions, profils, admin web et écrans mobiles concernés. La landing page a également été contrôlée par ses tests disponibles.

Les reproductions complémentaires appellent les fonctions réelles avec une base MongoDB simulée en mémoire, des comptes fictifs et des services externes neutralisés. Les cas de concurrence utilisent une synchronisation des lectures ; les cas d'interruption injectent une panne après une première écriture. Ce ne sont pas des tests HTTP de bout en bout et ils ne valident pas le comportement du déploiement réel. Le SDK Firebase absent localement a été remplacé uniquement pour permettre l'import des fonctions d'authentification ; la vérification Firebase n'a pas été testée ainsi.

### Contrôles exécutés

| Contrôle | Résultat | Limite |
| --- | --- | --- |
| Backend : sélection de tests unitaires sûrs | 313 tests réussis | Les anciens scripts susceptibles d'utiliser une vraie base ou un réseau externe ont été exclus |
| Mobile : suite de tests disponible | 183 tests réussis | Pas de validation matérielle Android/iOS |
| Mobile : analyse statique | Aucun problème signalé | SDK local différent de celui du build CI |
| Admin web : tests disponibles | 27 tests réussis | Pas de navigation de bout en bout |
| Admin web : TypeScript | Contrôle réussi | Ne valide ni l'ergonomie ni les règles métier |
| Landing page : tests disponibles | 4 tests réussis | Pas de test réel des liens universels sur téléphone |
| Scénarios diagnostiques complémentaires | 21 scénarios ont mis en évidence les comportements décrits | Données synthétiques, mocks et injections de panne |
| Dépendances web : `npm audit --omit=dev --json` | 7 paquets signalés : 1 critique, 4 élevés, 2 faibles | L'exploitabilité dépend des fonctions utilisées et de l'hébergement |
| Lint admin | Non validé : absence de configuration ESLint, commande interactive | Le contrôle ne peut pas servir de garde automatique en l'état |

Total des tests existants exécutés et réussis : **527**. Leur réussite n'annule pas les défauts reproduits ci-dessous.

## Défauts applicatifs

P0 : risque immédiat sur l'argent ou la preuve de remise. P1 : incohérence importante, sécurité ou blocage fonctionnel. P2 : fiabilité et expérience utilisateur.

### B01 — P0 — Répéter acceptation/libération crée du solde

Sources : [crédit wallet](C:/Users/Utilisateur/Pickupoint/backend/services/wallet_service.py:292), [revenus](C:/Users/Utilisateur/Pickupoint/backend/services/wallet_service.py:333), [débit à l'acceptation](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1467), [remboursement à la libération](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:2335).

Avec les commissions activées, une mission demandant 1 500 FCFA de commission et un wallet initial de 5 000 FCFA donne :

| Cycle sur la même mission | Après acceptation | Après libération |
| --- | --- | --- |
| Premier | 3 500 FCFA | 5 000 FCFA |
| Deuxième | 5 000 FCFA | 6 500 FCFA |
| Troisième | 6 500 FCFA | 8 000 FCFA |

L'historique contient pourtant seulement un débit et un remboursement. La référence de débit est réutilisée lors de la réacceptation ; l'ancien débit est alors considéré comme déjà exécuté. À l'inverse, `credit_wallet` modifie le solde avant de vérifier l'existence du mouvement.

Reproduction indépendante : deux crédits de 1 000 FCFA avec la même référence et `ensure_unique=True` produisent 2 000 FCFA de solde mais une seule ligne de crédit. Deux enregistrements du même revenu de 700 FCFA ajoutent aussi 1 400 FCFA au compteur de revenus pour une seule ligne de 700 FCFA.

Correction attendue : réserver une clé d'opération unique avant toute modification, rendre écriture comptable et modification du solde atomiques, distinguer chaque affectation de mission et son remboursement. Ajouter des tests de répétition, concurrence et reprise après panne. Réconcilier les soldes existants avant toute réparation de données ; ne pas lancer une correction automatique à l'aveugle.

### B02 — P0 — Le livreur reçoit des codes qu'il ne doit pas connaître

Sources : [liste des colis](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:636), [détail du colis](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:954), [route dédiée aux codes](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:1974).

Sur un colis domicile-domicile assigné au compte de test livreur, la liste expose le code de collecte et le code de livraison. Le détail expose également le code de livraison. Les restrictions de la route dédiée aux codes ne protègent pas ces autres réponses.

Impact : le code destiné au client perd sa valeur de preuve indépendante. Une protection uniquement dans l'écran ne suffit pas.

Correction attendue : un sérialiseur commun avec liste explicite des champs autorisés par rôle, appliqué à toutes les réponses, exports et métadonnées de timeline. Tester expéditeur, destinataire, livreur, relais et admin sur chaque mode de livraison.

### B03 — P0 — La route de remise relais peut éviter la vérification du PIN

Sources : [preuve de remise](C:/Users/Utilisateur/Pickupoint/backend/models/delivery.py:47), [remise au relais](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:1650).

Le PIN est vérifié uniquement si `proof_type == "pin"`. Le modèle accepte un texte quelconque. Avec `proof_type="unrecognized"`, sans PIN ni autre preuve, la route appelle la transition vers « livré ». La reproduction neutralise la transition finale pour observer cet appel sans effets externes.

Correction attendue : types de preuve fermés et vérification obligatoire de la preuve correspondant au flux. Refuser les valeurs inconnues et les preuves absentes ; prévoir une dérogation admin séparée, explicitement autorisée et journalisée si nécessaire.

### B04 — P1 — Deux acceptations simultanées donnent deux missions au même livreur

Source : [acceptation](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1399).

Le contrôle « aucune mission active » précède l'affectation et n'est pas une réservation atomique du livreur. Deux requêtes concurrentes sur deux missions différentes passent ce contrôle et affectent les deux missions au même compte.

Correction attendue : verrou/réservation atomique par livreur, avec un mécanisme de libération et de reprise fiable. La protection par mission seule ne garantit pas « une mission par livreur ».

### B05 — P1 — Une mission en incident n'empêche pas une nouvelle acceptation

Source : [statuts contrôlés à l'acceptation](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1401).

Le contrôle ne couvre que `assigned` et `in_progress`, alors que `incident_reported` est considéré comme actif dans d'autres parties du code. La reproduction obtient deux missions actives : celle en incident et une nouvelle affectation.

Correction attendue : utiliser la définition centrale des missions actives dans acceptation, dispatch, notifications, décaissements et présence.

### B06 — P1 — L'acceptation ne respecte pas toutes les restrictions de dispatch

Source : [acceptation](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1369).

Une mission en exclusivité réservée, par sa liste de candidats, à un autre livreur a été acceptée par le compte de test, sans position dans la requête. L'acceptation ne réutilise pas les contrôles de visibilité appliqués à la prévisualisation ; la réservation admin fait l'objet d'un contrôle distinct, elle n'est pas le problème reproduit.

Correction attendue : revérifier côté serveur l'éligibilité effective au moment d'accepter : étape du dispatch, exclusivité, disponibilité, éventuel refus et position requise. Une ancienne notification ne doit pas constituer une autorisation permanente.

### B07 — P1 — Une panne financière laisse « colis livré / mission en cours »

Sources : [transition du colis](C:/Users/Utilisateur/Pickupoint/backend/services/parcel_service.py:1211), [distribution financière](C:/Users/Utilisateur/Pickupoint/backend/services/parcel_service.py:1228), [clôture de mission](C:/Users/Utilisateur/Pickupoint/backend/services/parcel_service.py:1326).

Une panne injectée pendant la distribution des revenus laisse le colis `delivered` mais la mission `in_progress`. Le statut du colis a été écrit avant les opérations financières et la clôture. Une nouvelle tentative de la même transition peut ensuite être refusée.

La mise à jour du statut filtre uniquement sur l'identifiant du colis, sans comparer le statut lu : il existe aussi un risque de doubles effets sous concurrence, non reproduit de bout en bout ici.

Correction attendue : transition conditionnelle et opérations métier atomiques ou reprises par une file d'événements fiable. Une notification ou un service secondaire ne doit pas bloquer définitivement la clôture métier.

### B08 — P1 — Une panne de débit laisse une affectation partielle

Source : [débit après affectation](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1451).

Une erreur injectée dans le débit laisse la mission `assigned` alors que le colis n'a pas de livreur assigné. La remise en attente ne traite que `ValueError`, pas une erreur de base de données ou une interruption technique.

Correction attendue : traiter affectation, réservation du livreur et débit comme une opération cohérente, avec reprise ou compensation et vérification du résultat réel avant de recommencer.

### B09 — P1 — Le hash du PIN est inclus dans les réponses d'authentification

Sources : [modèle retourné](C:/Users/Utilisateur/Pickupoint/backend/models/user.py:91), [profil authentifié](C:/Users/Utilisateur/Pickupoint/backend/routers/auth.py:538).

Le modèle public `User` contient `pin_hash`. L'appel de la fonction de profil avec un compte fictif renvoie ce champ dans sa sérialisation. D'autres réponses d'authentification utilisent le même modèle.

Il s'agit du hash du compte authentifié, pas d'une preuve d'accès anonyme aux PIN des autres comptes. Ce secret n'a toutefois aucune raison d'être envoyé au client, aux outils de diagnostic ou à leurs logs.

Correction attendue : séparer modèles internes et modèles de réponse ; exclure le hash et les données de verrouillage dans toutes les sorties.

### B10 — P1 — Le verrouillage du PIN peut produire une erreur 500 persistante

Sources : [comparaison du verrouillage](C:/Users/Utilisateur/Pickupoint/backend/routers/auth.py:255), [configuration MongoDB](C:/Users/Utilisateur/Pickupoint/backend/database.py:44).

La comparaison entre une date MongoDB sans fuseau et `datetime.now(timezone.utc)` échoue avec `TypeError`. La reproduction utilise une date de verrouillage telle que MongoDB la restitue avec la configuration actuelle. Un compte verrouillé peut donc rencontrer une erreur 500 au lieu du message prévu, y compris après l'échéance tant que cette comparaison reste exécutée.

Correction attendue : normalisation UTC systématique et tests de lecture MongoDB, expiration du verrou et remise à zéro des compteurs.

### B11 — P1 — Modifier une préférence peut réactiver les autres notifications

Sources : [route utilisée par le mobile](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/api/api_endpoints.dart:41), [sauvegarde](C:/Users/Utilisateur/Pickupoint/backend/routers/auth.py:543), [valeurs du modèle](C:/Users/Utilisateur/Pickupoint/backend/models/user.py:31).

Sur un compte ayant désactivé push, WhatsApp et promotions, une modification partielle de `android_vibration` remet ces trois préférences à `true`. Le modèle complète les champs absents avec leurs valeurs par défaut, puis la route remplace l'objet de préférences.

Une sauvegarde partielle plus prudente existe dans une autre route utilisateur, mais ce n'est pas celle qu'appelle le mobile.

Correction attendue : fusionner uniquement les champs réellement fournis, harmoniser les routes et tester chaque commutateur avec les autres préférences désactivées. Ne jamais réactiver implicitement un choix marketing.

### B12 — P1 — Un compte sans lien avec le colis peut le noter plusieurs fois

Source : [notation](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:2021).

Un compte client fictif qui n'est ni expéditeur ni destinataire a noté trois fois le même colis livré. Le livreur a reçu trois unités dans le compteur d'avis et 30 XP alors qu'il n'existe qu'un seul colis noté. La route ne vérifie pas l'accès au colis et les effets sont réexécutés à chaque modification.

Correction attendue : contrôler l'auteur autorisé, rendre la création d'avis unique et traiter une modification éventuelle comme un remplacement sans nouveaux XP ni compteur supplémentaire.

### B13 — P1 — Un règlement relais validé peut redevenir « déclaré »

Source : [déclaration financière du relais](C:/Users/Utilisateur/Pickupoint/backend/routers/relay_points.py:182).

Après une validation admin d'un paiement à Denkma, une nouvelle déclaration du relais remet le même état à `declared`. L'écriture ne vérifie pas l'état précédent.

Correction attendue : machine d'états explicite et mise à jour conditionnelle. Un paiement finalisé ne peut être rouvert que par une action admin dédiée et traçable ; distinguer déclaration de paiement et réception réellement validée.

### B14 — P1 — La configuration peut être sauvegardée malgré une réponse d'échec

Sources : [mise à jour opérationnelle](C:/Users/Utilisateur/Pickupoint/backend/routers/admin.py:5802), [recalcul des commissions](C:/Users/Utilisateur/Pickupoint/backend/routers/admin.py:225).

Avec une mission historique dont le mode de livraison est vide, la sauvegarde renvoie 409 pendant le recalcul. Les paramètres globaux et le flag de commissions du colis ont pourtant déjà été écrits.

Correction attendue : validation préalable des données à recalculer, traitement explicite des dossiers invalides et atomicité ou résultat détaillé de mise à jour partielle. L'admin doit savoir ce qui a réellement changé.

### B15 — P2 — La vérification refuse les codes réservés au premier envoi

Source : [vérification du code promo](C:/Users/Utilisateur/Pickupoint/backend/routers/parcels.py:576).

Le paramètre `is_first_delivery` est toujours transmis à `False`. Pour un nouveau client sans colis livré, la vérification répond 404 tandis que le service de promotion confirme l'éligibilité lorsque le bon paramètre est fourni.

Correction attendue : appliquer la même règle d'éligibilité dans vérification, devis et création, sans simplification codée en dur.

### B16 — P1 — Les quotas promotionnels peuvent être dépassés

Sources : [vérification du quota](C:/Users/Utilisateur/Pickupoint/backend/services/promotion_service.py:67), [enregistrement de l'utilisation](C:/Users/Utilisateur/Pickupoint/backend/services/promotion_service.py:116).

Deux devis éligibles obtenus avant leur enregistrement peuvent consommer deux fois une promotion limitée à une utilisation totale et une utilisation par personne. La reproduction obtient `uses_count=2` et deux usages du même client pour une limite de 1.

Correction attendue : réservation atomique des quotas à la création, idempotence par colis et libération de la réservation si la création échoue.

### B17 — P1 — « Express offert » peut garder le supplément Express

Sources : [calcul Express](C:/Users/Utilisateur/Pickupoint/backend/services/pricing_service.py:260), [application de la promotion](C:/Users/Utilisateur/Pickupoint/backend/services/pricing_service.py:297), [offre Express](C:/Users/Utilisateur/Pickupoint/backend/services/promotion_service.py:81).

Dans un scénario synthétique avec prix normal de 1 000 FCFA et multiplicateur Express de 2, le devis Express reste à 2 000 FCFA tout en retournant `express_free=true`. Le supplément a été appliqué avant la promotion et celle-ci ne le retire pas.

Correction attendue : traiter l'offre avant le supplément ou recalculer explicitement le prix et le niveau de service. Vérifier que prix, prestation et texte affiché désignent la même offre.

### B18 — P2 — Une offre devenue indisponible annule la notification de la mission active

Sources : [réception en arrière-plan](C:/Users/Utilisateur/Pickupoint/mobile/lib/main.dart:65), [réception au premier plan](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/notifications/notification_service.dart:392), [synchronisation](C:/Users/Utilisateur/Pickupoint/mobile/lib/core/notifications/notification_service.dart:257), [invalidation serveur](C:/Users/Utilisateur/Pickupoint/backend/services/notification_service.py:1266).

Lecture croisée, sans reproduction sur téléphone : le signal `mission_unavailable` annule l'identifiant global de notification de mission active sans vérifier que sa référence est celle de cette mission. Si un livreur a pris A mais était auparavant candidat pour B, l'acceptation de B par un autre livreur peut retirer le chronomètre de A. Le cache local peut ensuite empêcher sa restauration tant que l'identifiant et l'échéance de A sont inchangés.

Correction attendue : annuler seulement l'offre correspondante, vérifier la mission concernée et resynchroniser la notification persistante. Confirmer le scénario sur Android réel au premier plan et en arrière-plan.

### B19 — P2 — Effacer la biographie ne la supprime pas

Sources : [normalisation du profil](C:/Users/Utilisateur/Pickupoint/backend/models/user.py:147), [sauvegarde](C:/Users/Utilisateur/Pickupoint/backend/routers/auth.py:547).

Une biographie existante reste présente après une sauvegarde avec une chaîne vide. La chaîne est normalisée en `None`, puis éliminée par `exclude_none=True`.

Correction attendue : distinguer « champ non fourni » et « demande explicite d'effacement ». Appliquer cette règle aux champs facultatifs concernés.

## Solde et revenus du livreur : problèmes et réorganisation recommandée

Sources : [composition de l'écran](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/driver/screens/driver_wallet_screen.dart:219), [recharges](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/driver/screens/driver_wallet_screen.dart:406), [mouvements](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/driver/screens/driver_wallet_screen.dart:546), [retraits visibles](C:/Users/Utilisateur/Pickupoint/mobile/lib/features/driver/screens/driver_wallet_screen.dart:592), [API d'historique](C:/Users/Utilisateur/Pickupoint/backend/routers/wallets.py:116).

Le problème signalé est confirmé par la lecture du code :

- Une recharge créditée figure dans « Recharges récentes » et dans « Mouvements ». Un retrait est aussi présenté dans plusieurs blocs.
- La demande de retrait produit un mouvement de réservation, puis sa validation un mouvement de débit. Les afficher comme deux lignes négatives non regroupées peut donner l'impression d'un double retrait. Ce constat d'affichage ne prouve pas deux débits réels du solde : l'API réserve le montant à la demande et diminue le montant réservé à l'approbation.
- Les revenus de livraison encaissés hors plateforme sont mêlés aux mouvements du solde. La mention « Revenu hors solde » existe, mais remplace le détail descriptif et ne constitue pas une vue claire des gains.
- Il n'y a pas de vrai résumé des revenus de la période dans cet écran intitulé « Solde et revenus ».
- Le filtre de période ne concerne que « Mouvements », pas les recharges et retraits placés au-dessus.
- Le mobile récupère au maximum 50 mouvements, ignore le total renvoyé et ne propose pas la pagination. La vue « Tout » n'affiche donc pas tout. Seuls trois retraits sont visibles, sans lien vers les autres dans cet écran.
- Une erreur de chargement des retraits masque la section, comme s'il n'existait aucune donnée.

### Organisation proposée

| Zone | Contenu | Règle de compréhension |
| --- | --- | --- |
| Solde Denkma | Disponible, montant réservé pour retrait, « Recharger », « Retirer » | Argent réellement disponible dans Denkma ; expliquer son usage pour couvrir les commissions |
| Revenus des courses | Période, gains enregistrés, nombre de missions, accès aux détails | Revenus hors plateforme, distincts du solde et des recharges ; calcul côté serveur sur la totalité de la période |
| À suivre | Recharges non confirmées et retraits en attente seulement | Actions utiles et statuts, pas un deuxième historique des opérations terminées |
| Historique | Une liste filtrable : recharges, commissions, remboursements, retraits | Une opération logique par référence, date, montant, effet réel sur le solde, statut et détail ; pagination accessible |

Les recharges et retraits terminés quittent « À suivre » et restent dans l'historique. Un retrait garde une seule présentation, avec l'évolution de son statut. Les courses restent accessibles dans l'historique des revenus et ouvrent leur récapitulatif.

Les montants agrégés ne doivent pas être calculés sur les 50 lignes chargées à l'écran. Les seuils et restrictions doivent provenir des règles backend. Pendant une demande de retrait, désactiver l'envoi pendant le traitement et prévoir une protection contre les doubles soumissions.

Cette réorganisation est proposée, pas implémentée pendant cet audit.

## GPS : couverture du parcours à préciser

Sources : [archivage des points](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1872), [import hors connexion](C:/Users/Utilisateur/Pickupoint/backend/routers/deliveries.py:1974), [trace retournée](C:/Users/Utilisateur/Pickupoint/backend/services/mission_trace.py:27).

L'archivage durable et la trace retournée commencent à `started_at`, c'est-à-dire après confirmation de collecte. La reproduction fournit deux points, l'un avant collecte et l'autre après ; la trace retournée contient seulement le second. Le trajet vers la collecte n'est donc pas inclus dans cette trace, même s'il a été visible en live et figure temporairement dans le buffer.

Si l'admin doit conserver le parcours complet depuis l'acceptation, c'est un écart fonctionnel à corriger : archiver les deux phases, les distinguer et calculer leurs distances séparément. Ne pas élargir pour autant le suivi client : conserver l'absence de suivi des flux relais non autorisés et l'accès du destinataire relais-domicile seulement après collecte.

## Dépendances et configuration : risques distincts des bugs reproduits

### Dépendances admin web

Le lockfile utilise Next.js `14.2.15` et Axios `1.15.0`. L'audit npm signale sept paquets : Next.js au niveau critique ; Axios, form-data, nanoid et PostCSS au niveau élevé ; esbuild et postcss-selector-parser au niveau faible. Il s'agit de paquets signalés, pas de sept exploits reproduits sur Denkma.

Les avis des mainteneurs confirment des versions concernées. Le contournement middleware Next.js dépend de contrôles d'autorisation placés dans ce middleware ; la route API garde ses propres contrôles dans ce projet. La faille d'optimisation AVIF dépend de l'utilisation de cette fonction et de ses bibliothèques sous-jacentes. L'avis Axios cité nécessite une pollution de prototype préalable, non démontrée ici. Sources : [avis Next.js middleware](https://github.com/vercel/next.js/security/advisories/GHSA-f82v-jwr5-mffw), [avis Next.js AVIF](https://github.com/vercel/next.js/security/advisories/GHSA-2xp9-vwfh-vxw4), [avis Axios](https://github.com/axios/axios/security/advisories/GHSA-pf86-5x62-jrwf).

Faire une mise à jour contrôlée et retester le build et l'adaptateur Cloudflare ; ne pas lancer `npm audit fix --force` sans examiner les changements majeurs. Aucun paquet n'a été mis à jour pendant cet audit.

### Vérifications de déploiement encore nécessaires

- Vérifier le support réel des transactions MongoDB : le fichier de développement utilise un MongoDB autonome, tandis que fidélité et parrainage comportent des opérations transactionnelles. Ne pas déduire de ce fichier la topologie de production.
- Vérifier l'activation effective du chiffrement KYC, de l'antivirus, de la MFA admin et les conditions de migration des pièces existantes. La présence du code et des tests ne prouve pas que les secrets et services ont été configurés. Voir [procédure KYC](../kyc-security.md).
- Vérifier Stripe en environnement de test : signature du webhook, rapprochement serveur, unicité du crédit, paiement différé et retour Android/iOS. Les tests simulés passent ; aucune clé, aucun webhook live ni paiement réel n'a été utilisé dans cet audit.
- Vérifier Shorebird et les liens de retour sur les builds réellement installés. Aucun nouveau build natif ni patch n'a été publié.
- Compléter l'analyse des dépendances backend et mobile avec les versions réellement installées en production ; l'audit npm concerne seulement l'admin web.
- Ajouter une configuration ESLint non interactive et une chaîne CI couvrant les scénarios nouveaux. Les dépendances backend largement non verrouillées limitent aussi la reproductibilité entre poste, tests et déploiement.

## Ordre recommandé pour les corrections

1. **Sécuriser les soldes et les preuves de remise** : B01, B02, B03, puis ajouter les tests de non-régression avant de diffuser les changements.
2. **Rendre les opérations métier cohérentes** : réservation d'un livreur, acceptation, libération, fin de course, règlements relais et sauvegardes admin. Traiter B04 à B08, B13 et B14.
3. **Protéger comptes, consentements et avis** : B09 à B12 et B19 ; valider les routes réellement utilisées par le mobile.
4. **Corriger les offres et les notifications** : B15 à B18, avec tests de quotas concurrents et essais Android réels.
5. **Réorganiser le wallet et compléter l'accès aux historiques**, puis valider le parcours complet client/livreur/relais/admin sur des données de test.
6. **Mettre à niveau les dépendances et vérifier le déploiement**, parallèlement aux corrections prioritaires et avant validation finale.

Toute réparation des données financières doit être précédée d'une sauvegarde et d'une réconciliation explicite. Les défauts backend exigent un déploiement backend ; un patch mobile seul ne peut pas les corriger.
