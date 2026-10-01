# Recharge du solde livreur par carte

## Fonctionnement

Le montant minimum et le maximum viennent du serveur (`WALLET_TOPUP_MIN_XOF` et `WALLET_TOPUP_MAX_XOF`). L'application affiche ces limites et refuse un montant invalide avant de créer le paiement. Le serveur vérifie à nouveau le montant, qui doit être un nombre entier de FCFA.

Stripe Checkout ouvre le navigateur. Le retour par défaut est `/app/?wallet_return=success&topup_id=…`, ou `wallet_return=cancel` en cas de retour sans confirmation. La page `/app/` propose le retour dans l'application avec un lien déjà déclaré dans Android et iOS. Si le navigateur bloque l'ouverture automatique, le bouton « Retourner dans Denkma » reste accessible.

L'application ouvre « Solde et revenus » et vérifie la recharge auprès du serveur. Elle actualise le solde puis les mouvements, également au retour du navigateur, avec le bouton d'actualisation ou en tirant la page vers le bas. Une confirmation retardée est revérifiée un nombre limité de fois, uniquement au premier plan. Les états des recharges sont visibles dans « Recharges récentes ».

Le retour `success` ne constitue jamais une preuve de paiement. Le crédit repose sur une confirmation Stripe : signature du webhook, ou consultation de la session avec la clé serveur. Le montant, la devise XOF, la session, la recharge, le compte et le solde concernés doivent correspondre. La récupération par API contrôle aussi que le paiement n'est pas remboursé ou contesté.

Un marqueur écrit atomiquement avec le crédit dans le document du solde empêche une recharge d'être créditée deux fois, même si le webhook et l'actualisation arrivent ensemble. Le mouvement possède un identifiant stable. Une reprise après interruption complète le mouvement et l'état sans réappliquer le crédit. Les mouvements existants sont respectés. La recharge n'augmente pas les gains de livraison.

## Activation en production

1. Déployer le backend avec les clés Stripe du même compte et du même mode que les paiements. Aucun secret n'est nécessaire dans l'application ou la landing page.
2. Dans Stripe, vérifier le webhook `https://api.denkma.com/api/webhooks/stripe`, son secret `STRIPE_WEBHOOK_SECRET`, les événements `checkout.session.completed` et, si utilisés, `checkout.session.async_payment_succeeded`. Examiner les tentatives de livraison dans Stripe en cas d'erreur.
3. Publier les fichiers de la landing : `app/index.html`, `assets/open-app.js`, `assets/wallet-return.js`, `wallet/stripe/success/index.html` et `wallet/stripe/cancel/index.html`. Les deux dernières pages réparent les anciens chemins de retour et conservent la référence de recharge.
4. Si `STRIPE_WALLET_SUCCESS_URL` ou `STRIPE_WALLET_CANCEL_URL` sont définies, vérifier qu'elles pointent vers une des pages prévues. Le backend conserve la configuration et ajoute les paramètres de retour.
5. Publier les changements Dart sur une release Shorebird compatible. Ce correctif ne change aucun fichier natif, dépendance ou numéro de version. Cela ne remplace pas la vérification de compatibilité avec la release ciblée.
6. Vérifier sur Android et iPhone l'ouverture depuis le navigateur, le retour à froid et à chaud et le bouton de secours. Les liens universels iOS nécessitent une association de domaine valide ; le lien de secours utilise le schéma déjà enregistré.

## Patch de la release 47

Le `pubspec.yaml` et les workflows de patch Android et iOS ciblent explicitement `1.0.27+47`, sans `latest`. Utiliser les workflows **Android Shorebird Patch** et **iOS Shorebird Patch**, pas les workflows de release ou de publication Google Play. Ne pas remplacer les variables de version par `latest` dans Codemagic.

Avant toute préparation native, le workflow compare les sources à l'état Git `d4f0b04419db8df9d9889019619a6e3516e451ee`, préparé pour la release 47. Il refuse les différences dans les dossiers natifs, le verrou des dépendances, les assets et la configuration de l'application. Après installation, les versions et empreintes des plugins Android et iOS résolus sont contrôlées à nouveau ; une différence dans un outil de test Dart n'est pas assimilée à un changement natif. Shorebird sélectionne ensuite le SDK de la release ciblée et conserve sa propre vérification des artefacts : aucun contournement `--allow-native-diffs` ou `--allow-asset-diffs` n'est utilisé.

La comparaison Git et les tests locaux ne remplacent pas la comparaison avec les artefacts réels enregistrés chez Shorebird. Aucun build Codemagic ni patch Shorebird n'a été lancé pour cette préparation.

## Paiement déjà reçu, mais non crédité

Après déploiement du backend, l'actualisation du solde recherche les recharges `pending` de ce compte qui possèdent une session Stripe enregistrée. Les paiements confirmés peuvent donc être récupérés sans nouvelle recharge, y compris depuis l'ancienne application.

Si la recharge reste non confirmée, ne pas payer une seconde fois. Vérifier le mode Stripe, la session associée à la recharge et les événements du webhook. Une session absente ou une incohérence nécessite une investigation par le support ; aucun crédit n'est inventé ou déduit de la seule capture d'écran.

Ce correctif ne traite pas automatiquement les remboursements ou contestations de recharges déjà créditées. Ceux-ci nécessitent une procédure financière distincte.

## Paramètres de vérification

- `STRIPE_HTTP_TIMEOUT_SECONDS` : délai d'une requête Stripe (6 secondes par défaut).
- `STRIPE_RECONCILE_INTERVAL_SECONDS` : intervalle minimal entre deux vérifications d'une recharge (10 secondes).
- `STRIPE_RECONCILE_LIMIT` : nombre maximal de sessions vérifiées par actualisation (5).
- `STRIPE_RETURN_RETRY_ATTEMPTS` : revérifications supplémentaires dans l'application après le retour (3).
- `WALLET_TOPUP_HISTORY_LIMIT` : nombre de recharges récentes renvoyées (10).

Les erreurs Stripe ne doivent pas être exposées avec des données de paiement ou des secrets. Les réponses du solde sont servies sans cache.

## Vérifications locales

- Backend : `python -m unittest test_stripe_wallet_flow -v` depuis `backend/`.
- Mobile : `flutter test --no-pub test/wallet_topup_test.dart` depuis `mobile/`.
- Landing : `node --test landing/tests/open-app.test.cjs` depuis la racine.

Ces tests simulent Stripe et la base de données. Ils ne créent aucun paiement réel et ne prouvent pas à eux seuls que le webhook de production est correctement configuré.
