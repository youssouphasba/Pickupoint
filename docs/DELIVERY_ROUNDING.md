# Arrondis des nouvelles courses en FCFA

La politique `customer_down_driver_up_v1` s’applique aux nouveaux devis. Le pas de caisse provient de `DELIVERY_ROUNDING_STEP_XOF` (50 FCFA par défaut). Aucun taux de commission supplémentaire n’est imposé dans l’application.

## Calcul et configuration admin

1. Le serveur calcule le tarif selon le mode, la distance, le poids, l’express, la fidélité et les promotions applicables.
2. Il conserve ce tarif avant arrondi et les taux configurés pour ce mode dans l’admin.
3. Le prix client est arrondi vers le bas. La part théorique du livreur est arrondie vers le haut. Chaque part relais est arrondie vers le bas.
4. La commission Denkma est le prix client moins les parts finales du livreur et des relais. Le solde minimum demandé au livreur est exactement la somme des commissions finales Denkma et relais.

Exemple avec un tarif de 2 337 FCFA et les taux 70 % livreur, 15 % relais et 15 % Denkma : client 2 300, livreur 1 650, relais 350, Denkma 300, solde minimum 650 FCFA.

Avec les taux personnalisés 55 % livreur, 25 % relais et 20 % Denkma : client 2 300, livreur 1 300, relais 550, Denkma 450, solde minimum 1 000 FCFA.

Les pourcentages admin sont des bases de calcul, pas la répartition effective après arrondi. Cette dernière est conservée sur le colis et la mission et utilisée pour le blocage du solde, les règlements, l’historique et la finance admin.

## Protection et historique

- La répartition est calculée et vérifiée côté serveur ; une valeur affichée ou envoyée par le téléphone ne remplace pas ce calcul.
- La confirmation mobile transmet le prix affiché. Si le tarif ou la promotion a changé, aucun colis ni paiement n’est créé avant une nouvelle confirmation du devis actualisé.
- Un nouveau devis créé conserve ses taux et son pas d’arrondi. Les mises à jour admin ne modifient pas rétroactivement ces conditions.
- Un changement de destination avant prise en charge peut établir un nouveau devis avec ces taux conservés. Les courses payées, affectées ou ayant un contrat financier ne sont pas repricées automatiquement ; les flux de redirection conservent leur contrat.
- Les anciens colis conservent leur politique et leurs commissions historiques. Il n’y a ni migration de leurs prix, ni modification de leurs paiements ou prélèvements existants.
- Les surcoûts de changement d’adresse pendant une course restent des compléments distincts, soumis à leur acceptation existante ; ils ne sont pas ajoutés artificiellement aux avantages d’arrondi du devis initial.
- Si les arrondis conduisent à une commission Denkma négative, le devis est refusé avec une erreur explicite. Cela concerne notamment un tarif non arrondi avec commissions désactivées : aucun surcoût client, réduction du gain livreur ou financement non autorisé n’est inventé.

## Indication verte

Le client voit l’économie entre le tarif avant arrondi et son prix final. Le livreur voit le complément entre sa part théorique et son gain final, avec la mention « inclus dans votre gain ». L’admin distingue ces avantages de la réduction réelle de marge Denkma, qui tient aussi compte des parts relais arrondies.

L’espace livreur n’affiche jamais le prix total client, y compris dans le détail des missions, les informations de règlement et les notifications de règlement. Les réponses des API de missions et de l’historique du solde destinées aux livreurs excluent les prix client et les répartitions complètes ; elles conservent le gain, le complément offert et le solde requis. Les statuts de paiement et les blocages de remise restent calculés sur les données complètes côté serveur. Les vues client, relais et admin ne sont pas modifiées.

Les différences théoriques peuvent comporter des décimales ; elles sont informatives et ne constituent jamais une demande de paiement fractionnaire. Les montants effectivement répartis pour les nouveaux devis restent des multiples du pas de caisse. Aucun deuxième crédit n’est ajouté au gain déjà arrondi. Une ancienne course sans données d’arrondi ne reçoit pas d’avantage fictif.

## Livraison et vérifications

Les modifications de cette fonctionnalité concernent le backend, l’admin web et le Dart mobile, sans nouveau plugin, permission, asset ou code natif. Le déploiement backend et la mise à jour de l’admin et de l’application sont nécessaires pour les observer. Les autres modifications natives présentes dans le dépôt sont indépendantes de cette fonctionnalité.

Les tests couvrent les quatre modes, les taux personnalisés, les promotions, les limites décimales, les données incohérentes, la conservation des conditions, la confirmation d’un tarif changé et l’absence de double crédit.
