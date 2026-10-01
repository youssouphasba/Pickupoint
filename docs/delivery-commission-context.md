# Contexte des commissions de livraison

## Origine de l'erreur

La liste des missions récupérait uniquement le prix et les contacts du colis.
Les missions conservaient les taux configurés, mais pas le mode de livraison.
Le calcul recevait alors un mode vide et échouait avec `KeyError: ''`.
L'ouverture d'une ancienne notification révélait le défaut en rechargeant la liste.

## Calcul et compatibilité

- Les nouvelles missions conservent le mode original du colis dans `delivery_mode`.
- Les anciennes missions récupèrent ce mode et le contexte financier depuis leur colis associé, sans migration de données.
- Un mode explicite de mission reste prioritaire pour préserver son contexte historique. Un champ vide n'écrase pas le mode du colis.
- Les règles enregistrées sur la mission restent prioritaires. Si elles sont absentes, les règles du colis sont utilisées avant le mécanisme historique existant.
- Une préférence de commission explicitement désactivée reste respectée.
- Les taux et montants déjà enregistrés ne sont pas modifiés par ce correctif.
- Le mode ne se déduit pas des étapes GPS/relais : une étape de transit ne décrit pas nécessairement le mode contractuel du colis.

## Données réellement incomplètes

Une mission dont le mode est manquant ou invalide n'utilise aucun mode arbitraire :

- elle est exclue des courses proposées, sans bloquer les autres courses ;
- les historiques restent présents avec leurs montants enregistrés ;
- son aperçu et son acceptation renvoient un conflit HTTP 409 avec un message explicite ;
- aucune écriture sur la mission ni opération de wallet n'est effectuée lors de cette acceptation refusée.

La synthèse Finance charge également les colis associés aux missions de la période même si ces colis ont été créés auparavant.
Les commissions impossibles à calculer sont exclues des totaux, avec une alerte « Commissions non calculables — totaux partiels » et les références à vérifier. Aucun montant nul fictif n'est affiché pour ces anomalies.

## Vérification

`backend/test_delivery_commission_context.py` couvre les quatre modes avec des taux configurés distincts, la projection MongoDB, les anciennes notifications, la création des missions, les refus d'acceptation et la synthèse Finance.
Les tests HTTP s'exécutent avec une base simulée et ne modifient aucune donnée réelle.

Le correctif concerne uniquement le backend et ne nécessite ni modification native ni nouvelle release mobile.
