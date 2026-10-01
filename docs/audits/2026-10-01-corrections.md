# Bilan des corrections — 1er octobre 2026

Version mobile conservée : `1.0.28+48`. Aucun paiement, aucune migration financière et aucune réparation automatique des données de production.

## Changements

- Soldes, retraits, commissions et remboursements : opérations transactionnelles, références distinctes par affectation, répétitions idempotentes, reprise après interruption.
- Affectations : réservation atomique du livreur, incident considéré comme mission active, vérification des restrictions de disponibilité et du dispatch à l’acceptation.
- Remise au relais : preuve PIN obligatoire ; codes et jetons de confirmation filtrés selon le destinataire des réponses.
- Livraison : clôture métier et revenus dans la même transaction ; compléments secondaires repris par une file persistante.
- Comptes : hash PIN exclu des réponses publiques, dates de verrouillage normalisées, consentements non réactivés par sauvegarde partielle, effacement explicite des champs facultatifs.
- Avis, règlements relais et configuration : autorisations, écritures conditionnelles et protections contre les répétitions.
- Promotions : quota atomique, réservation également lorsque le devis devient disponible après confirmation GPS, conservation de l’offre réservée, prix et service Express cohérents.
- Notifications : une ancienne disponibilité consulte les courses actuellement accessibles ; plusieurs ouvrent « Disponibles », une seule ouvre son aperçu, aucune affiche un état explicite. Les offres devenues indisponibles n’annulent plus la notification de mission active.
- Wallet livreur : solde disponible et réservé, revenus encaissés hors plateforme séparés, agrégats serveur sur toute la période, opérations en attente distinctes, historique paginé et retraits regroupés.
- GPS admin : trace depuis l’affectation, phases avant/après collecte distinguées. Les restrictions du suivi client restent inchangées.
- Admin : configuration ESLint non interactive et mise à jour contrôlée des dépendances ; absence de vulnérabilité signalée par `npm audit --omit=dev` après installation.
- Android : remplacement de la lecture globale des contacts par `ACTION_PICK` sur un numéro. Seuls le nom et le numéro choisis sont lus ; `READ_CONTACTS` et `WRITE_CONTACTS` sont retirées du manifeste fusionné via les directives `tools:node="remove"`. Le parcours iOS reste inchangé.

## Contrôles et limites

- Tests mobile : 190 réussis, dont quatre tests du pont de sélection de contact et les scénarios de navigation des notifications.
- Analyse Flutter : aucun problème signalé.
- Tests admin : 27 réussis ; TypeScript et lint réussis séparément.
- Backend : 340 tests réussis. Exécuter depuis `backend` : `python -m tests.run_regressions`. Cette sélection exclut les anciens scripts susceptibles d’appeler des données ou services réels. Les nouveaux tests simulent transactions, répétitions et pannes ; ils ne remplacent pas un essai concurrent sur un replica set réel.
- Le build Next.js compile les sources, puis échoue faute d’espace disque pendant le contrôle des types. Le build complet et l’adaptateur Cloudflare doivent être validés sur la CI avant mise en production.
- La compilation native Android et le comportement du sélecteur sur téléphone ne sont pas confirmés localement. Les tests Dart ne valident pas l’application Contacts d’un constructeur.
- Aucun nouveau binaire mobile, patch Shorebird, paiement réel ou déploiement manuel n’a été exécuté.

## Prérequis de diffusion

1. Vérifier que MongoDB est un replica set ou un cluster supportant les transactions avant déploiement backend. Le démarrage refuse désormais une base autonome ; le Compose de développement initialise un replica set. Ne pas lancer une conversion de production sans sauvegarde et procédure dédiée.
2. Tester sur base isolée les affectations concurrentes, recharges Stripe, retraits, libérations et clôtures. Réconcilier les soldes historiques séparément : corriger le code ne répare pas les écritures anciennes.
3. Valider le build admin et l’adaptateur d’hébergement.
4. Faire une **release Android complète**, pas un patch Shorebird seul, pour retirer les permissions et intégrer le sélecteur natif. Vérifier sélection, annulation, plusieurs numéros et retour dans le formulaire sur le Galaxy S24 Ultra.
5. Confirmer sur Android les notifications au premier plan, en arrière-plan et au démarrage à froid. Le backend doit aussi être déployé pour les corrections serveur.
