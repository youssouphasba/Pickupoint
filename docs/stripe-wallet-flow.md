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

## Release 48 et prochains patches

Le `pubspec.yaml` prépare `1.0.28+48`. Cette version contient des changements natifs Android et un nouvel asset de logo : publier d'abord une nouvelle release Android et iOS. Elle ne peut pas être distribuée comme patch de la version 47.

Les workflows de patch Android et iOS utilisent désormais `latest`. Tant que la release 48 n'est pas enregistrée chez Shorebird pour la plateforme concernée, cette cible peut encore désigner la release 47. Ne pas lancer un patch de ces sources avant la nouvelle release. Vérifier la version cible affichée par Shorebird avant publication.

`SHOREBIRD_PATCH_BASE_REF` est optionnel et non déclaré par défaut : Codemagic refuse une variable déclarée avec une chaîne vide. Les scripts acceptent son absence. Pour renforcer les contrôles, le renseigner avec le commit exact de la release ciblée : le workflow vérifie les sources, puis les versions et empreintes des plugins résolus. Ne pas réutiliser une référence de la release 47 pour la 48. Shorebird conserve dans tous les cas sa vérification des artefacts : aucun contournement `--allow-native-diffs` ou `--allow-asset-diffs` n'est utilisé.

Les nouvelles releases et les patches des deux plateformes utilisent `--no-tree-shake-icons` pour conserver la police complète des icônes Material. Ce réglage ne remplace pas la police déjà embarquée dans une ancienne release 47 et ne rend pas les nouveaux assets patchables.

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
