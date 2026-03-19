# BUSINESS PLAN — DENKMA
### Plateforme de livraison intelligente et réseau de points relais pour le Sénégal
**Version 1.0 — Mars 2026**

---

## TABLE DES MATIÈRES

1. Résumé exécutif
2. Problème et opportunité de marché
3. Solution Denkma
4. Analyse de marché
5. Modèle économique et tarification
6. Stratégie opérationnelle
7. Produit et technologie
8. Stratégie marketing et acquisition
9. Organisation et équipe
10. Plan financier et projections
11. Analyse des risques
12. Feuille de route et jalons
13. Annexes

---

## 1. RÉSUMÉ EXÉCUTIF

**Denkma** est une plateforme technologique de livraison du dernier kilomètre conçue spécifiquement pour le marché sénégalais. Elle combine un réseau de **points relais** (boutiques partenaires, stations, commerces de proximité) avec une flotte de **livreurs indépendants**, orchestrés par une application mobile unique.

**Le problème** : Au Sénégal, la livraison de colis est freinée par l'absence d'adresses postales formalisées, la perte de temps considérable (appels, attente, coordination), le manque de confiance dans les services existants, et des coûts élevés pour le dernier kilomètre. Les solutions internationales (DHL, FedEx) sont inaccessibles pour le marché local, et les alternatives informelles manquent de traçabilité et de fiabilité. Les super-apps (Yango, Yassir) se concentrent sur la food delivery et ne proposent pas de réseau de points relais.

**Notre solution** : Denkma propose 4 modes de livraison flexibles (relais-à-relais, relais-à-domicile, domicile-à-relais, domicile-à-domicile), un système de **géolocalisation de bout en bout** (adresse GPS, dispatch par proximité, suivi temps réel du livreur, preuve de livraison GPS), et une intégration native avec les moyens de paiement locaux (Wave, Orange Money, Free Money). Le réseau de points relais résout le problème d'adressage en offrant des lieux de dépôt et de retrait connus et accessibles.

**Modèle de revenus** : Commission de **15 %** prélevée sur chaque livraison. Tarifs accessibles à partir de **700 XOF** (~1,07 EUR) avec des suppléments transparents (distance, poids, express) qui bénéficient aussi aux livreurs.

**Marché cible** : Les 18,6 millions d'habitants du Sénégal, avec un focus initial sur la zone urbaine de Dakar (4 millions d'habitants). Le e-commerce sénégalais a généré 287 millions USD en 2024 avec une croissance de 15-20 %/an, et le taux de pénétration mobile atteint 128,7 %.

**Investissement de départ** : **10 000 EUR** (fonds propres), concentré sur le recrutement de points relais, le marketing terrain, les parrainages et les offres de lancement. L'application est déjà développée et déployée.

**Objectif à 12 mois** : 100 points relais actifs à Dakar, 50 livreurs, 2 500 livraisons mensuelles. Rentabilité opérationnelle (mode solo) atteignable dès le mois 9-10.

---

## 2. PROBLÈME ET OPPORTUNITÉ DE MARCHÉ

### 2.1 Le problème de la livraison au Sénégal

Le Sénégal, comme la majorité des pays d'Afrique de l'Ouest, fait face à des défis structurels majeurs en matière de logistique du dernier kilomètre :

**Absence d'adresses formelles**
La plupart des habitations sénégalaises n'ont pas d'adresse postale normalisée. Les indications reposent sur des repères informels ("en face de la mosquée", "après le baobab, 3e maison à gauche"). Cette réalité rend toute livraison à domicile incertaine, coûteuse en temps, et source de frustration pour l'expéditeur comme le destinataire. Selon AfriGIS, les données d'adresses incomplètes ou inexactes sont le premier facteur d'échec de livraison en Afrique, entraînant des tentatives multiples et des clients insatisfaits ¹.

**Perte de temps massive pour les expéditeurs et destinataires**
L'envoi ou la réception d'un colis au Sénégal est aujourd'hui synonyme de **perte de temps considérable**. Un expéditeur doit enchaîner les appels téléphoniques pour trouver un coursier disponible, négocier le tarif, expliquer l'itinéraire par des repères visuels, puis attendre — parfois des heures — que le coursier se présente. Côté destinataire, l'attente est encore plus frustrante : aucune visibilité sur l'heure d'arrivée, des appels répétés au coursier ("tu es où ?"), des créneaux entiers de la journée bloqués à attendre une livraison qui peut ne jamais arriver.

À l'échelle du continent, **5 à 20 % des livraisons échouent dès la première tentative** en raison de l'adressage imprécis ². Chaque échec entraîne un nouveau cycle d'appels, de coordination et d'attente. Le coût d'une livraison échouée est estimé à **17,78 USD par colis** en coûts directs (re-livraison, service client, logistique), et jusqu'à **25-40 USD** en impact total incluant la perte de clients ³. Pour les consommateurs, ce temps perdu — estimé à **30-60 minutes par livraison** en coordination et attente dans les marchés informels — est un frein majeur à l'adoption du e-commerce et à l'envoi de colis entre particuliers.

**Coûts élevés et manque de transparence**
Les services de livraison existants pratiquent des tarifs opaques, souvent négociés de gré à gré. Il n'existe pas de grille tarifaire standard, et le client ne sait pas à l'avance combien coûtera sa livraison. Les coursiers informels ("jakartamen") offrent un service rapide mais sans aucune garantie : pas de suivi, pas d'assurance, pas de recours en cas de perte. En Afrique, le coût du dernier kilomètre représente **35 à 55 % du prix du produit**, contre 28 % en moyenne mondiale ⁴ — un écart qui pèse directement sur le pouvoir d'achat des consommateurs.

**L'impasse de l'adressage classique — la géolocalisation comme seule issue**
Dans un pays où les rues n'ont souvent pas de nom et les maisons pas de numéro, les systèmes d'adressage traditionnels sont inopérants. Les services postaux classiques (La Poste, boîtes postales) couvrent moins de 5 % de la population. Même les applications GPS grand public (Google Maps, Waze) sont imprécises dans les quartiers populaires de Dakar : rues non cartographiées, bâtiments non référencés, indications qui mènent au milieu d'un carrefour. Le livreur finit invariablement par appeler le destinataire pour se faire guider par téléphone — un processus qui rallonge chaque livraison de 10 à 30 minutes et qui échoue si le destinataire ne décroche pas. **La seule solution fiable est de capturer les coordonnées GPS exactes au moment de la commande**, directement depuis le smartphone de l'utilisateur, plutôt que de se fier à une adresse textuelle approximative.

**Confiance et traçabilité**
L'absence de traçabilité des colis est le frein principal à l'adoption du e-commerce. La majorité des acheteurs en ligne sénégalais déclarent préférer le retrait en boutique à la livraison, par manque de confiance dans les services de livraison existants. Sans suivi, l'expéditeur ne sait pas si son colis est en route, livré, ou perdu. Le destinataire ne peut pas prouver qu'il n'a rien reçu. Le livreur ne peut pas prouver qu'il a bien livré. Ce manque de preuve génère des litiges impossibles à trancher.

**Fragmentation de l'offre**
Le marché est fragmenté entre des acteurs internationaux (chers et peu adaptés), des startups locales (couverture limitée), et un réseau informel de coursiers (fiable mais non scalable). Aucun acteur ne combine réseau de points relais + livraison à domicile + suivi temps réel + paiement mobile + **géolocalisation de précision**.

> **Sources section 2.1 :**
> ¹ [AfriGIS — Last Mile Delivery and E-Commerce Solutions](https://www.afrigis.co.za/last-mile-delivery-and-e-commerce-solutions/)
> ² [SmartRoutes — Last-Mile Delivery Statistics 2025](https://smartroutes.io/blogs/last-mile-delivery-statistics-the-complete-data-resource/)
> ³ [Veho — True Cost of Failed Deliveries](https://www.shipveho.com/blog/what-is-the-true-cost-of-failed-deliveries-in-e-commerce) ; [GoBolt — Last Mile Delivery Issues](https://www.gobolt.com/blog/last-mile-delivery-issues/)
> ⁴ [eTrade for All / ITC — Logistics Update Africa: Getting Past the Hurdles to the Last Mile](https://etradeforall.org/news/logistics-update-africa-getting-past-hurdles-last-mile)

### 2.2 L'opportunité

**Croissance du e-commerce**
Le marché du e-commerce au Sénégal a généré **287 millions USD de revenus en 2024**, avec une croissance projetée de **15-20 % par an** ⁵. À l'échelle continentale, le marché africain du e-commerce, évalué à 1,64 milliard USD en 2025, devrait atteindre 6,74 milliards USD d'ici 2034, soit un TCAC de 17 % ⁶. Le Sénégal est parmi les marchés les plus dynamiques du continent, porté par :

- Un **taux de pénétration mobile de 128,7 %** (23,93 millions de connexions actives pour 18,6 millions d'habitants), dont 98,3 % en prépayé ⁷
- Plus de **80 % des adultes sénégalais possèdent un compte mobile money**, avec 38 millions de comptes enregistrés — une multiplication par 5 en 10 ans ⁸. Wave domine (~50-70 % de part de marché), suivi d'Orange Money (~25-30 %) et Free Money (~5-10 %) ⁸
- Le plan gouvernemental **"Sénégal Numérique 2025"** renforce le cadre légal du e-commerce, facilite l'interopérabilité des services financiers électroniques, et soutient la création de plateformes marchandes ⁹
- L'essor du **commerce social** (WhatsApp, Instagram, Facebook Marketplace) crée une demande de livraison fiable pour des milliers de micro-entrepreneurs

**Taille du marché adressable**

- **TAM (Total Addressable Market)** : Le marché de la livraison du dernier kilomètre en Afrique est évalué à **1,58 milliard USD en 2025**, avec une projection à **3,02 milliards USD d'ici 2033** (TCAC de 8,45 %) ¹⁰. En incluant le Moyen-Orient, certaines estimations portent le marché combiné MEA à 24,5 milliards USD en 2024 ¹¹.

- **SAM (Serviceable Addressable Market)** : Le marché sénégalais de la logistique et du fret s'inscrit dans un marché ouest-africain évalué à **27,58 milliards USD en 2025** ¹². La part du dernier kilomètre au Sénégal, rapportée au poids économique du pays dans la sous-région (~8-10 % du PIB de la CEDEAO), est estimée entre **120 et 160 millions USD**.

- **SOM (Serviceable Obtainable Market)** : Part capturable à 3 ans — **2-3 %** du SAM soit **3-5 millions USD**, en se concentrant sur Dakar et les 4 principales villes secondaires.

**Facteurs favorables**

- **Dakar, un terrain idéal** : Avec **4 millions d'habitants** et une densité de **7 350 hab/km²**, la métropole dakaroise concentre 25 % de la population nationale et 50 % de la population urbaine ¹³. Cette densité est optimale pour un réseau de points relais à maillage serré.
- **Démographie favorable** : Population du Sénégal estimée à **18,6 millions en 2025**, dont 53 % en zone urbaine ¹⁴. L'âge médian de 18 ans signifie une population nativement digitale.
- L'expansion de Wave et Orange Money démocratise le paiement digital — les volumes de transactions mobile money ont bondi de **41 % entre 2022 et 2023** après le déploiement national de la 4G ⁸
- Les commerçants de proximité (boutiques de quartier) constituent un maillage naturel pour les points relais, avec une boutique pour environ 200 habitants dans les quartiers populaires de Dakar

> **Sources section 2.2 :**
> ⁵ [Statista — eCommerce Senegal Market Forecast](https://www.statista.com/outlook/emo/ecommerce/senegal) ; [ECDB — E-Commerce Industry in Senegal](https://ecdb.com/resources/sample-data/market/sn/all)
> ⁶ [Market Data Forecast — Africa E-Commerce Market Size 2034](https://www.marketdataforecast.com/market-reports/africa-e-commerce-market)
> ⁷ [TechAfrica News — Senegal's Mobile Connections Grow 4.4% in 2025](https://techafricanews.com/2026/03/17/senegals-mobile-connections-grow-4-4-in-2025-despite-q4-subscriber-loss/) ; [DataReportal — Digital 2025: Senegal](https://datareportal.com/reports/digital-2025-senegal)
> ⁸ [GSMA — Senegal Mobile Money Evaluation](https://www.gsma.com/solutions-and-impact/connectivity-for-good/mobile-for-development/wp-content/uploads/2025/03/Senegal.pdf) ; [Hub2 — Understand How People Pay in Senegal](https://www.hub2.io/understand-how-people-pay-in-senegal/)
> ⁹ [Lloyds Bank Trade — E-commerce in Senegal](https://www.lloydsbanktrade.com/en/market-potential/senegal/ecommerce)
> ¹⁰ [Straits Research — Africa Last Mile Delivery Market Size 2033](https://straitsresearch.com/report/africa-last-mile-delivery-market)
> ¹¹ [Business Market Insights — Middle-East & Africa Last Mile Delivery Market to 2031](https://www.businessmarketinsights.com/reports/middle-east-and-africa-last-mile-delivery-market)
> ¹² [Mordor Intelligence — West Africa Freight and Logistics Market](https://www.mordorintelligence.com/industry-reports/west-africa-freight-and-logistics-market)
> ¹³ [MacroTrends — Dakar Metro Area Population](https://www.macrotrends.net/global-metrics/cities/22439/dakar/population) ; [MobiliseYourCity — Factsheet Dakar 2025](https://www.mobiliseyourcity.net/sites/default/files/2025-05/Dakar,%20Senegal.pdf)
> ¹⁴ [Worldometer — Senegal Population 2026](https://www.worldometers.info/world-population/senegal-population/)

---

## 3. SOLUTION DENKMA

### 3.1 Proposition de valeur

Denkma est la **première plateforme de livraison hybride** au Sénégal, combinant :

1. **La géolocalisation comme fondation** : Là où l'adressage textuel échoue, Denkma place le GPS au coeur de chaque étape. Le système repose sur 5 usages clés de la géolocalisation :

   - **Adresse par GPS, pas par texte** : À la création d'un colis, l'expéditeur et le destinataire positionnent un marqueur sur la carte (Google Maps SDK) pour indiquer le point exact d'enlèvement et de livraison. Cette coordonnée GPS (latitude/longitude) remplace l'adresse postale et élimine toute ambiguïté. Un champ texte optionnel permet d'ajouter un complément ("2e étage, porte bleue") et une **note vocale** pour guider le livreur à la voix.

   - **Dispatch intelligent par proximité** : Lorsqu'un colis est prêt à être enlevé, le système calcule la distance Haversine entre le point d'enlèvement et chaque livreur disponible, puis propose la mission aux livreurs dans un **rayon de 5 km**, triés par proximité croissante. Pas de dispatching manuel, pas d'appels — le livreur le plus proche est sollicité en premier.

   - **Suivi en temps réel du livreur** : Pendant la livraison, la position GPS du livreur est partagée en temps réel avec l'expéditeur et le destinataire (rafraîchissement toutes les 5 secondes). Le client voit le livreur approcher sur la carte — fini l'angoisse du "il est où ?". L'itinéraire optimal est calculé et affiché via Google Maps Directions API.

   - **Preuve de livraison par géolocalisation** : À l'enlèvement comme à la livraison, le livreur confirme sa présence par **validation GPS**. Le système vérifie que les coordonnées du livreur correspondent au point prévu (avec une tolérance de proximité). Cette preuve GPS horodatée est enregistrée dans l'historique immutable du colis — elle protège le livreur, l'expéditeur et le destinataire en cas de litige.

   - **Tarification précise à la distance** : Le prix de chaque livraison est calculé automatiquement à partir de la distance GPS réelle (formule Haversine) entre le point d'enlèvement et le point de livraison. Plus de tarif "au feeling" — le client voit un devis instantané, transparent et reproductible, basé sur les coordonnées exactes.

2. **Un réseau de points relais** : des boutiques de quartier, stations-service, et commerces partenaires qui servent de points de dépôt et de retrait. Chaque relais est géolocalisé dans l'app avec ses horaires, sa capacité disponible, et un indicateur de distance depuis la position de l'utilisateur. Pour les zones où le GPS du destinataire est imprécis ou inaccessible (ruelles étroites, zones non cartographiées), le relais offre un **point de chute fiable** avec une adresse connue.

3. **Une flotte de livreurs indépendants** : des coursiers géolocalisés en permanence, dispatchés automatiquement par proximité, rémunérés à la commission.

4. **4 modes de livraison flexibles** :
   - **Relais → Relais** (700 XOF) : Le plus économique. L'expéditeur dépose au relais, le destinataire retire au relais. Aucune coordonnée domicile nécessaire.
   - **Relais → Domicile** (1 100 XOF) : Dépôt en relais, livraison GPS au domicile du destinataire.
   - **Domicile → Relais** (900 XOF) : Enlèvement GPS chez l'expéditeur, dépôt en relais.
   - **Domicile → Domicile** (1 300 XOF) : Service premium porte-à-porte, 100 % guidé par GPS.

5. **Paiement mobile natif** : Wave, Orange Money, Free Money — les moyens de paiement que les Sénégalais utilisent quotidiennement.

### 3.2 Parcours utilisateur

**Client expéditeur** :
1. Ouvre l'app → S'inscrit via téléphone + OTP (30 secondes)
2. Crée un colis → Choisit le mode de livraison → Obtient un devis instantané
3. Paie via Wave/Orange Money/Free Money
4. Dépose au relais (ou attend l'enlèvement à domicile)
5. Suit son colis en temps réel → Reçoit une notification à la livraison

**Client destinataire** :
1. Reçoit une notification WhatsApp/SMS avec le code de suivi
2. Se rend au relais (ou attend la livraison à domicile)
3. Présente son code PIN pour retirer le colis
4. Confirme la réception dans l'app ou par SMS

**Livreur** :
1. Voit les missions disponibles triées par proximité
2. Accepte une mission → Reçoit les coordonnées GPS
3. Récupère le colis → Confirme par scan QR
4. Livre → Confirme par géolocalisation GPS
5. Reçoit sa commission instantanément dans son portefeuille

**Point relais** :
1. Reçoit un colis → Scanne le QR code (entrée en stock)
2. Gère son inventaire dans l'app
3. Remet le colis au destinataire ou au livreur → Vérifie le PIN
4. Reçoit sa commission automatiquement

### 3.3 Différenciateurs clés

| Critère | Coursiers informels | Concurrents tech | Denkma |
|---|---|---|---|
| Adresse par GPS | Non (repères oraux) | Texte + GPS optionnel | GPS natif + carte + note vocale |
| Suivi temps réel du livreur | Non | Partiel | GPS temps réel (5s) + timeline |
| Preuve de livraison | Aucune | Photo parfois | Validation GPS horodatée + immutable |
| Tarification par distance GPS | Non (négocié) | Forfait ou zone | Haversine au mètre près |
| Dispatch par proximité | Non (appels) | Manuel ou aléatoire | Auto (rayon 5 km, tri par distance) |
| Points relais géolocalisés | Non | Rare | Réseau dédié avec distance affichée |
| 4 modes livraison | Non | 1-2 modes | 4 modes flexibles |
| Paiement mobile | Cash uniquement | Limité | Wave/OM/FM natif |
| Notes vocales guidage | Non | Non | Oui (enregistrement audio in-app) |
| Gamification livreurs | Non | Non | XP, badges, bonus mensuels |

---

## 4. ANALYSE DE MARCHÉ

### 4.1 Marché cible

**Segment primaire — Particuliers urbains (C2C)**
- 4 millions d'habitants à Dakar
- Envois familiaux, cadeaux, achats en ligne
- Sensibles au prix, habitués au mobile money
- Volume estimé : 60 % des livraisons

**Segment secondaire — Commerçants et e-commerçants (B2C)**
- 15 000+ vendeurs actifs sur les réseaux sociaux au Sénégal
- Boutiques Instagram/WhatsApp en pleine croissance
- Besoin de solution fiable et économique
- Volume estimé : 30 % des livraisons

**Segment tertiaire — Entreprises (B2B)**
- PME avec besoins logistiques réguliers
- Documents, échantillons, pièces détachées
- Prêts à payer plus pour la fiabilité
- Volume estimé : 10 % des livraisons

### 4.2 Analyse concurrentielle

**Concurrents directs au Sénégal** :

| Acteur | Type | Forces | Faiblesses |
|---|---|---|---|
| **Yango Delivery** | Filiale Yandex (Russie) | Marque internationale, app mature, présence Dakar/Thiès/Mbour, offre Cargo (jusqu'à 1 000 kg), food delivery lancé en 2025 ¹⁵ | Modèle généraliste (VTC + food + colis) — pas spécialisé colis C2C. Pas de points relais. Tarification opaque à la course (modèle taxi appliqué au colis). Pas de suivi colis post-dépôt. Pas de gamification livreurs. Dépendance à la maison mère russe (risque géopolitique/sanctions). |
| **Yassir** | Super-app algérienne | Levée de fonds importante (>150M USD total), partenariat Carrefour Sénégal, présence Dakar/Thiès/Saly, +2 000 produits livrables ¹⁶ | Focus food & groceries, pas de service colis C2C dédié. Pas de points relais. Modèle "livraison en -1h" inadapté aux colis inter-quartiers programmés. Pas de preuve de livraison GPS. Expansion rapide mais rentabilité non prouvée en Afrique de l'Ouest. |
| **Yobante Express** | Startup sénégalaise | Présence établie, réseau de livreurs locaux, connaissance du terrain | Pas de points relais, UX datée, pas de suivi temps réel, pas de gamification |
| **Paps** | Startup sénégalaise | Bonne tech, investisseurs, API B2B | Focus B2B, cher pour les particuliers, pas de réseau relais |
| **Mon Coursier** | Startup sénégalaise | Marque connue à Dakar | Couverture limitée à Dakar centre, pas de scalabilité sous-régionale |
| **Jakartamen (informel)** | Coursiers moto indépendants | Rapide, pas cher, omniprésent | Aucune traçabilité, aucune garantie, aucun suivi, tarif négocié |

**Positionnement face à Yango et Yassir** :

Yango et Yassir sont des **super-apps généralistes** (VTC + food + courses) qui ajoutent la livraison comme service complémentaire. Leur modèle est celui du **transport à la demande** : un coursier prend un colis et le livre immédiatement, comme une course taxi. Ce modèle fonctionne bien pour la food delivery mais présente des limites structurelles pour la **livraison de colis entre particuliers** :

- **Pas de stockage intermédiaire** : Si le destinataire n'est pas disponible, le colis est retourné. Denkma résout ce problème via le réseau de relais.
- **Pas de flexibilité temporelle** : Le colis doit être livré immédiatement. Denkma permet le dépôt en relais et le retrait quand le destinataire est disponible (jusqu'à 7 jours).
- **Pas de preuve de livraison solide** : Yango et Yassir n'offrent pas de confirmation GPS horodatée ni d'event sourcing immutable.
- **Tarification à la course** : Le prix dépend de la demande en temps réel (surge pricing), peu prévisible. Denkma offre un devis instantané basé sur la distance GPS réelle.
- **Pas de réseau relais** : L'avantage structurel de Denkma est son maillage de points relais, une infrastructure que les super-apps ne peuvent pas répliquer rapidement car elle nécessite du recrutement terrain, de la formation, et de la gestion opérationnelle par quartier.

**Avantage concurrentiel Denkma** :
1. **Réseau de points relais** : Aucun concurrent (y compris Yango et Yassir) ne propose un maillage de points relais dédiés — c'est une barrière à l'entrée physique
2. **Tarif relais-à-relais à 700 XOF** : Le tarif le plus bas du marché, impossible à atteindre avec un modèle "course taxi"
3. **4 modes de livraison** : Flexibilité unique — du 100 % relais (économique) au 100 % domicile (premium), le client choisit
4. **Géolocalisation de bout en bout** : Adresse GPS, dispatch par proximité, suivi temps réel, preuve de livraison GPS — une chaîne complète que les concurrents n'offrent que partiellement
5. **Gamification livreurs** : XP, badges, classement, bonus — rétention supérieure face au turnover des flottes Yango/Yassir
6. **Spécialisation colis C2C** : Là où les super-apps diluent leur attention entre VTC, food et courses, Denkma est 100 % focalisé sur la livraison de colis

> **Sources section 4.2 :**
> ¹⁵ [Yango Delivery Sénégal](https://delivery.yango.com/sn-fr) ; [DakarActu — Yango lance l'offre Cargo à Dakar](https://www.dakaractu.com/Yango-Delivery-lance-l-offre-Cargo-pour-les-colis-volumineux-a-Dakar_a257426.html) ; [Capsud — Yango accompagne la restauration](https://capsud.net/2025/02/25/economie-numerique-yango-senegal-accompagne-les-acteurs-de-la-restauration/)
> ¹⁶ [Yassir — Super App](https://yassir.com/) ; [SeneWeb — Yassir et Carrefour](https://www.seneweb.com/en/news/Societe/yassir-senegal-et-carrefour-unissent-leurs-forces-pour-revolutionner-lexperience-dachat-au-senegal_n_441488.html) ; [Africanews — Yassir seeks to conquer world](https://www.africanews.com/2022/04/10/algeria-s-homegrown-startup-yassir-seeks-to-conquer-world/)

### 4.3 Analyse SWOT

| | Positif | Négatif |
|---|---|---|
| **Interne** | **Forces** : Tech robuste, géolocalisation de bout en bout, 4 modes, réseau relais (barrière physique), paiement mobile natif, gamification livreurs | **Faiblesses** : Pas encore de marque établie, dépendance aux relais partenaires, pas de levée de fonds réalisée |
| **Externe** | **Opportunités** : Croissance e-commerce 17%/an, digitalisation (Sénégal Numérique 2025), 80% adultes sur mobile money, expansion sous-régionale | **Menaces** : Yango/Yassir pourraient ajouter un service relais, régulation du transport de colis, résistance au changement des jakartamen |

---

## 5. MODÈLE ÉCONOMIQUE ET TARIFICATION

### 5.1 Sources de revenus

**Revenu principal — Commission sur livraisons (15 %)**

Denkma prélève une commission fixe de **15 %** sur chaque livraison effectuée. Cette commission est transparente et intégrée au prix affiché au client.

Exemple pour une livraison relais-à-relais à 1 000 XOF :
- Plateforme Denkma : 150 XOF (15 %)
- Livreur : 700 XOF (70 %)
- Relais origine : 75 XOF (7,5 %)
- Relais destination : 75 XOF (7,5 %)

**Revenus secondaires (Phase 2)** :
- **Abonnements commerçants** : Forfait mensuel pour les e-commerçants (accès API, volume garanti)
- **Publicité et promotions sponsorisées** : Visibilité des relais/commerçants dans l'app
- **Services à valeur ajoutée** : Assurance colis, livraison express garantie, emballage
- **API B2B** : Intégration logistique pour les plateformes e-commerce tierces

### 5.2 Grille tarifaire détaillée

#### Prix de base par mode

| Mode | Base (XOF) | Commission livreur | Commission relais | Plateforme |
|---|---|---|---|---|
| Relais → Relais | 700 | 70 % | 7,5 % x 2 relais | 15 % |
| Relais → Domicile | 1 100 | 70 % | 15 % (origine) | 15 % |
| Domicile → Relais | 900 | 70 % | 15 % (destination) | 15 % |
| Domicile → Domicile | 1 300 | 85 % | — | 15 % |

#### Suppléments — appliqués au prix total avant répartition des commissions

Les suppléments ci-dessous s'ajoutent au prix de base **avant** le calcul des commissions. Puisque la commission du livreur est un pourcentage du prix total (70 % ou 85 %), **chaque supplément augmente directement les gains du livreur** — c'est un levier d'attractivité et de motivation majeur.

| Facteur | Montant | Impact sur le gain livreur (70 %) |
|---|---|---|
| Distance | +100 XOF / km (calcul Haversine GPS) | +70 XOF / km pour le livreur |
| Poids (au-delà de 2 kg) | +100 XOF / kg supplémentaire | +70 XOF / kg pour le livreur |
| Livraison express | x1,30 (majoration 30 % sur le total) | Gain livreur x1,30 aussi |
| Livraison nuit/dimanche | x1,20 (majoration 20 % sur le total) | Gain livreur x1,20 aussi |

#### Exemples concrets de gains livreur (livraisons courantes < 2 000 XOF)

**Livraison économique** — Relais → Relais, 3 km, 1 kg :
- Prix total : 700 + (3 × 100) = 1 000 XOF
- Gain livreur : 1 000 × 70 % = **700 XOF**
- Gain relais A : 75 XOF · Gain relais B : 75 XOF · Plateforme : 150 XOF

**Livraison standard** — Relais → Relais, 5 km, 1 kg :
- Prix total : 700 + (5 × 100) = 1 200 XOF
- Gain livreur : 1 200 × 70 % = **840 XOF**

**Livraison avec poids** — Domicile → Relais, 4 km, 4 kg :
- Base + distance + poids : 900 + 400 + 200 = 1 500 XOF
- Gain livreur : 1 500 × 70 % = **1 050 XOF**

**Livraison express** — Relais → Domicile, 4 km, 1 kg :
- Base + distance : 1 100 + 400 = 1 500 XOF
- Express × 1,30 = 1 950 XOF → arrondi **1 950 XOF**
- Gain livreur : 1 950 × 70 % = **1 365 XOF** (soit +63 % vs la même course sans express)

**Effet multiplicateur pour un livreur actif** : Un livreur réalisant **8 livraisons/jour** avec un panier moyen de 1 200 XOF gagne environ 1 200 × 70 % × 8 = **6 720 XOF/jour**, soit ~**168 000 XOF/mois** (25 jours travaillés). Avec les bonus de performance (jusqu'à 15 000 XOF/mois), le revenu total peut atteindre **183 000 XOF/mois** (~279 EUR). Un livreur qui cible les courses express et nocturnes peut dépasser les **200 000 XOF/mois**.

#### Coefficient dynamique (pricing intelligent)

Un coefficient contextuel (0,80 à 2,00) ajuste le prix total en fonction de :
- La demande en temps réel (pics = coefficient plus élevé)
- La disponibilité des livreurs dans la zone
- Les conditions météorologiques
- Les événements spéciaux (Tabaski, Korité, etc.)

Ce coefficient **amplifie aussi les gains des livreurs** — en période de forte demande (coefficient 1,50), un livreur gagne 50 % de plus par course, ce qui incite les livreurs à être disponibles quand la demande est la plus forte. Le coefficient est enregistré pour chaque livraison, alimentant un futur modèle de machine learning pour l'optimisation tarifaire.

#### Arrondi

Tous les prix sont arrondis au **multiple de 50 XOF supérieur** pour faciliter les transactions en espèces et mobile money. L'arrondi bénéficie au livreur puisque sa commission est calculée sur le prix arrondi.

### 5.3 Économie unitaire (unit economics)

**Panier moyen estimé** : 1 200 XOF par livraison

| Métrique | Montant (XOF) | % |
|---|---|---|
| Prix moyen livraison | 1 200 | 100 % |
| Commission plateforme (15 %) | 180 | 15 % |
| Coût serveur/SMS par livraison | -5 | -0,4 % |
| Coût paiement (Flutterwave ~1,4 %) | -17 | -1,4 % |
| **Marge nette par livraison** | **158** | **13,2 %** |

**Point mort opérationnel (fondateur seul)** : Charges mensuelles ~348 000 XOF / 158 XOF marge nette = **~2 200 livraisons/mois**, atteignable entre le mois 9 et 10 selon les projections.

---

## 6. STRATÉGIE OPÉRATIONNELLE

### 6.1 Réseau de points relais

**Critères de sélection des relais** :
- Boutique avec pignon sur rue dans un quartier résidentiel ou commercial
- Ouvert au minimum 10h/jour, 6j/7
- Capacité de stockage de 20+ colis simultanés
- Gérant avec smartphone et connexion internet

**Types de relais** :

| Type | Description | Capacité | Commission |
|---|---|---|---|
| **Standard** | Boutique de quartier, télécentre, pressing | 20 colis | 7,5-15 % |
| **Station** | Station-service, hub de transport, superette | 50+ colis | 7,5-15 % |

**Proposition de valeur pour les relais** :
- Revenu complémentaire (7,5-15 % par colis traité)
- Augmentation du trafic piéton dans la boutique
- Bonus de performance (2 000 XOF/mois si 50+ colis traités)
- Visibilité dans l'application (vitrine digitale)

**Objectif de couverture** :
- Phase 1 (0-6 mois) : 50 relais à Dakar (quartiers prioritaires : Plateau, Médina, Parcelles Assainies, Pikine, Guédiawaye)
- Phase 2 (7-12 mois) : 100 relais à Dakar (+ Almadies, Ouakam, Ngor, Grand Yoff, Cambérène)
- Phase 3 (13-18 mois) : 150+ relais (densification Dakar + éventuellement Thiès/Mbour si la demande émerge)

### 6.2 Flotte de livreurs

**Profil du livreur Denkma** :
- Indépendant (pas salarié), rémunéré à la commission
- Équipé d'un smartphone et d'un moyen de transport (moto, vélo, voiture)
- Formé via l'application (tutoriel intégré)
- Évalué par les clients (système 5 étoiles)

**Dispatch intelligent** :
- Les missions sont proposées aux livreurs dans un rayon de **5 km** autour du point d'enlèvement
- Tri par **proximité croissante** (le plus proche en premier)
- **Auto-release** : Si un livreur n'a pas confirmé l'enlèvement en 15 minutes, la mission est réattribuée automatiquement

**Gamification et fidélisation** :

| Mécanisme | Détail |
|---|---|
| **Système XP** | 10 XP par livraison + bonus notation |
| **Niveaux** | Progression tous les 100 XP |
| **Badges** | "Premier Vol" (1 livraison), "Road Warrior" (10), "Légende de Dakar" (50), "Général 5 étoiles" (note 4.8+) |
| **Bonus mensuels** | 2 500 à 10 000 XOF selon volume et taux de réussite |
| **Classement** | Ranking mensuel visible dans l'app |

**Grille de bonus mensuels livreurs** :

| Condition | Bonus (XOF) |
|---|---|
| 200+ livraisons | 10 000 |
| 100-199 livraisons | 5 000 |
| 50-99 livraisons | 2 500 |
| Taux de réussite 95 %+ et 20+ missions | 5 000 (cumulable) |

### 6.3 Gestion des incidents

**Machine d'états du colis** :

Chaque colis suit un cycle de vie rigoureux avec des transitions contrôlées :

```
CRÉÉ → DÉPOSÉ AU RELAIS ORIGINE → EN TRANSIT → AU RELAIS DESTINATION
                                                      ↓
                     DISPONIBLE AU RELAIS → LIVRÉ
                           ↑
ÉCHEC LIVRAISON → REDIRIGÉ VERS RELAIS
```

États terminaux : LIVRÉ, ANNULÉ, EXPIRÉ, LITIGE, RETOURNÉ

**Mécanismes de sécurité** :
- **Codes PIN** : 6 chiffres pour le retrait en relais, vérification obligatoire
- **Confirmation GPS** : Preuve de livraison par géolocalisation
- **Event sourcing** : Chaque transition est un événement immutable, créant un historique complet
- **Notes vocales** : Instructions audio de l'expéditeur et du destinataire pour faciliter la localisation
- **Expiration automatique** : Colis non récupérés après 7 jours → statut EXPIRÉ + notification

---

## 7. PRODUIT ET TECHNOLOGIE

### 7.1 Architecture technique

**Backend** :
- **Framework** : FastAPI (Python) — haute performance asynchrone
- **Base de données** : MongoDB Atlas (cloud, scalable, répliqué)
- **ORM** : Motor (driver async MongoDB) + Pydantic V2 (validation)
- **Hébergement** : Railway (PaaS, déploiement continu)
- **Notifications** : Firebase Cloud Messaging + WhatsApp Cloud API (Meta)

**Mobile** :
- **Framework** : Flutter (cross-platform iOS/Android avec un seul codebase)
- **State management** : Riverpod (réactif, testable)
- **Navigation** : go_router (routing basé sur les rôles utilisateur)
- **Cartographie** : Google Maps SDK (géolocalisation, itinéraires, polylines)
- **Paiement** : InAppWebView (redirection Flutterwave sécurisée)

**Intégrations tierces** :
- **Flutterwave** : Passerelle de paiement (Wave, Orange Money, Free Money, cartes)
- **Firebase Auth** : Authentification OTP par téléphone
- **Google Maps API** : Calcul d'itinéraires, géocodage, distance
- **WhatsApp Cloud API** : Notifications transactionnelles
- **Twilio** : SMS de secours (fallback)

### 7.2 Sécurité

- Authentification par téléphone + OTP (6 chiffres, expiration 10 min)
- Tokens JWT (120 min accès, 30 jours refresh)
- Stockage sécurisé des tokens (FlutterSecureStorage, chiffrement OS)
- Rate limiting sur tous les endpoints sensibles
- Validation des rôles côté serveur (RBAC)
- Event sourcing immutable pour l'audit
- Chiffrement HTTPS en transit

### 7.3 Scalabilité

L'architecture choisie permet une montée en charge progressive :
- MongoDB Atlas : auto-scaling, sharding disponible
- FastAPI async : 10 000+ requêtes/seconde par instance
- Railway : scaling horizontal (ajout d'instances)
- Flutter : déploiement simultané iOS + Android
- Pas de dépendance à un serveur physique

---

## 8. STRATÉGIE MARKETING ET ACQUISITION

### 8.1 Positionnement

**Slogan** : "Denkma — La livraison qui vous comprend"

**Positionnement** : Solution de livraison **accessible, fiable et locale**. Denkma n'est pas un service premium pour les expatriés, c'est l'outil de livraison du quotidien pour tous les Sénégalais.

### 8.2 Stratégie d'acquisition

**Phase 1 — Lancement solo (Mois 1-3)** — Budget limité, focus terrain et viralité

| Canal | Action | Budget mensuel |
|---|---|---|
| Terrain (fondateur) | Recrutement relais quartier par quartier, démarchage direct | 100 000 XOF (déplacements) |
| WhatsApp | Groupes communautaires, forwarding viral, support client | 0 |
| Instagram/Facebook | Contenus vidéo "avant/après" livraison, reels, stories | 100 000 XOF (boost posts) |
| Parrainage | 500 XOF offerts au parrain et au filleul (1ère livraison) | ~150 000 XOF/mois |
| Offres de lancement | 1ère livraison gratuite (relais→relais) pour les premiers clients | Inclus dans budget investissement (voir 10.1) |
| Flyers/stickers relais | Matériel pour les boutiques partenaires | 50 000 XOF |
| **Total Phase 1** | | **~540 000 XOF/mois (~82 EUR)** |

**Phase 2 — Croissance organique (Mois 4-6)** — Accélération si traction confirmée

| Canal | Action | Budget mensuel |
|---|---|---|
| Parrainage renforcé | Augmentation à 750 XOF parrain + filleul si bonne conversion | ~250 000 XOF |
| Partenariats e-commerçants | Démarchage des vendeurs Instagram/WhatsApp de Dakar | 0 (fondateur) |
| Micro-influenceurs | 2-3 influenceurs locaux (10K-30K followers), échange de services | 100 000 XOF |
| Référencement | Google My Business pour chaque point relais | 0 (travail fondateur) |
| **Total Phase 2** | | **~350 000 XOF/mois (~53 EUR)** |

**Phase 3 — Structuration (Mois 7-12)** — Si le volume justifie des recrutements

| Canal | Action | Budget mensuel |
|---|---|---|
| Marketing digital | Campagnes Facebook/Instagram ciblées Dakar | 200 000 XOF |
| Événements | Présence sur 1-2 marchés/foires par mois (Sandaga, HLM) | 100 000 XOF |
| Partenariats B2C | Intégration avec e-commerçants locaux | 0 (équipe) |
| **Total Phase 3** | | **~300 000 XOF/mois (~46 EUR)** |

### 8.3 Programme de fidélité

**Système à 3 niveaux** :

| Niveau | Points requis | Avantage |
|---|---|---|
| **Bronze** | 0 - 199 | Accès standard |
| **Argent** | 200 - 499 | **10 % de réduction** sur toutes les livraisons |
| **Or** | 500+ | **20 % de réduction** sur toutes les livraisons |

**Gain de points** : 10 points par livraison réussie

Un client atteint le niveau Argent après ~20 livraisons et le niveau Or après ~50 livraisons, créant un effet de rétention fort.

### 8.4 Promotions

Le système de promotions intégré supporte :
- **Pourcentage** : -X % sur une livraison
- **Montant fixe** : -X XOF
- **Livraison gratuite** : 0 XOF (acquisition)
- **Upgrade express gratuit** : Express sans surcoût

Ciblage possible : tous les clients, première livraison uniquement, niveau fidélité spécifique, mode de livraison spécifique.

---

## 9. ORGANISATION ET ÉQUIPE

### 9.1 Structure organisationnelle

**Phase 1 (Mois 1-6) — Fondateur seul**

Le fondateur gère l'intégralité des opérations en s'appuyant sur l'automatisation de la plateforme :

| Fonction | Gestion par le fondateur |
|---|---|
| **Opérations** | Recrutement relais (terrain), formation livreurs (via l'app), gestion des incidents |
| **Technique** | Maintenance de l'app (déjà développée), corrections, déploiement Railway |
| **Marketing** | Réseaux sociaux, démarchage terrain, partenariats e-commerçants |
| **Support client** | WhatsApp Business (réponses directes + messages automatisés) |
| **Administratif** | Comptabilité simple, suivi des métriques, relation Flutterwave |

L'application automatise la majorité des tâches opérationnelles : dispatch des livreurs, suivi des colis, paiements, notifications, calcul des commissions, gestion des stocks relais. Le fondateur se concentre sur le **recrutement terrain** et le **support humain** pour les cas non couverts par l'app.

**Phase 2 (Mois 7-12) — Premiers recrutements si le volume le justifie**

Condition de déclenchement : **1 500+ livraisons/mois** ET traction confirmée (rétention > 30 %)

| Poste | Profil | Salaire estimé (XOF/mois) |
|---|---|---|
| **Agent terrain / opérations** | Recrutement relais, formation, présence terrain | 150 000 - 200 000 |
| **Support client / community manager** | WhatsApp, réseaux sociaux, gestion litiges | 150 000 - 200 000 |

**Phase 3 (Mois 13-18) — Structuration si croissance soutenue**

Condition : **5 000+ livraisons/mois**. Ajout progressif selon les besoins :
- 1 agent terrain supplémentaire (expansion nouveaux quartiers)
- 1 responsable commercial (partenariats e-commerçants)

### 9.2 Évolution des effectifs

| Période | Effectif | Masse salariale mensuelle (XOF) | Masse salariale (EUR) |
|---|---|---|---|
| Mois 1-6 | 1 (fondateur) | 0 (autofinancé) | 0 |
| Mois 7-12 | 3 (fondateur + 2) | 350 000 | ~53 |
| Mois 13-18 | 5 (si croissance) | 750 000 | ~114 |

> **Note** : Le fondateur ne se verse pas de salaire pendant les 12 premiers mois. La rémunération du fondateur viendra des revenus de la plateforme une fois le point mort atteint.

---

## 10. PLAN FINANCIER ET PROJECTIONS

### 10.1 Investissement initial — 10 000 EUR (6 550 000 XOF)

L'application mobile et le backend sont **déjà développés et déployés** — l'investissement de départ ne concerne que le lancement commercial.

| Poste | Montant (XOF) | Montant (EUR) | Détail |
|---|---|---|---|
| Recrutement points relais | 1 500 000 | 2 290 | Déplacements terrain, matériel (flyers, stickers, affiches), petits cadeaux de bienvenue relais |
| Marketing & réseaux sociaux | 1 200 000 | 1 830 | Boost Facebook/Instagram (6 mois), création de contenus vidéo |
| Offres de lancement | 900 000 | 1 370 | 1ère livraison gratuite (1 300 premières livraisons × ~700 XOF absorbés) |
| Parrainage (6 premiers mois) | 1 000 000 | 1 530 | Budget parrain + filleul (500 XOF × 2 × ~1 000 parrainages) |
| Infrastructure cloud (12 mois) | 600 000 | 915 | Railway (~$5/mois) + MongoDB Atlas (free tier puis ~$10/mois) + domaine |
| Frais Flutterwave / APIs | 350 000 | 534 | Frais paiement + Google Maps API (premiers mois faible volume) |
| Fonds de roulement | 1 000 000 | 1 530 | Trésorerie de sécurité (imprévus, retards de paiement) |
| **TOTAL** | **6 550 000** | **~10 000** | |

### 10.2 Projections de revenus (12 mois)

#### Hypothèses

- Panier moyen : 1 200 XOF (livraisons intra-Dakar, < 2 000 XOF)
- Commission plateforme : 15 % = 180 XOF/livraison
- Marge nette plateforme : 158 XOF/livraison (après frais paiement et cloud)
- Croissance progressive liée au recrutement de relais et au bouche-à-oreille
- Fondateur seul les 6 premiers mois, +2 employés à partir du mois 7
- Taux de rétention client : 35 % à 3 mois

#### Projections mensuelles

| Mois | Relais | Livreurs | Livraisons | CA brut (XOF) | Commission 15 % (XOF) | Charges (XOF) | Résultat net (XOF) |
|---|---|---|---|---|---|---|---|
| 1 | 10 | 5 | 100 | 120 000 | 18 000 | 348 000 | -330 000 |
| 2 | 15 | 8 | 150 | 180 000 | 27 000 | 348 000 | -321 000 |
| 3 | 20 | 10 | 220 | 264 000 | 39 600 | 348 000 | -308 400 |
| 4 | 30 | 14 | 330 | 396 000 | 59 400 | 348 000 | -288 600 |
| 5 | 40 | 18 | 500 | 600 000 | 90 000 | 348 000 | -258 000 |
| 6 | 50 | 22 | 700 | 840 000 | 126 000 | 348 000 | -222 000 |
| 7 | 60 | 28 | 950 | 1 140 000 | 171 000 | 860 000 | -689 000 |
| 8 | 70 | 33 | 1 200 | 1 440 000 | 216 000 | 860 000 | -644 000 |
| 9 | 80 | 38 | 1 500 | 1 800 000 | 270 000 | 860 000 | -590 000 |
| 10 | 90 | 43 | 1 900 | 2 280 000 | 342 000 | 860 000 | -518 000 |
| 11 | 95 | 48 | 2 200 | 2 640 000 | 396 000 | 860 000 | -464 000 |
| 12 | 100 | 50 | 2 500 | 3 000 000 | 450 000 | 860 000 | -410 000 |

#### Résumé année 1

| Indicateur | Année 1 (cumulé) |
|---|---|
| Livraisons totales | ~12 250 |
| CA brut cumulé | 14 700 000 XOF (~22 440 EUR) |
| Commission plateforme cumulée | 2 205 000 XOF (~3 365 EUR) |
| Charges totales cumulées | 7 248 000 XOF (~11 065 EUR) |
| **Déficit cumulé avant capital** | **-5 043 000 XOF (~-7 700 EUR)** |
| **Capital initial** | **6 550 000 XOF (10 000 EUR)** |
| **Trésorerie fin année 1** | **~1 507 000 XOF (~2 300 EUR)** |

> Le projet **ne consomme pas tout le capital** sur l'année 1 grâce aux commissions qui rentrent dès le mois 1. La trésorerie reste positive tout au long de la période, avec ~2 300 EUR de marge de sécurité à 12 mois.

### 10.3 Structure de coûts mensuels

#### Mois 1-6 (fondateur seul)

| Poste | Montant mensuel (XOF) | EUR |
|---|---|---|
| Infrastructure cloud (Railway + MongoDB Atlas) | 10 000 | 15 |
| SMS / WhatsApp / Notifications (faible volume) | 5 000 | 8 |
| Google Maps API (faible volume) | 5 000 | 8 |
| Frais Flutterwave (~1,4 % du CA brut) | ~8 000 | 12 |
| Marketing (boost réseaux + flyers) | 100 000 | 153 |
| Parrainage + offres lancement | 150 000 | 229 |
| Déplacements terrain (fondateur) | 50 000 | 76 |
| Divers (téléphone, internet) | 20 000 | 30 |
| **TOTAL Mois 1-6** | **~348 000** | **~531** |

> **L'app est déjà développée et déployée** — zéro coût de développement. Les coûts cloud sont minimaux grâce aux tiers gratuits (MongoDB Atlas free tier, Railway starter).

#### Mois 7-12 (fondateur + 2 employés)

| Poste | Montant mensuel (XOF) | EUR |
|---|---|---|
| Salaires (2 employés) | 350 000 | 534 |
| Infrastructure cloud (volume en hausse) | 25 000 | 38 |
| SMS / WhatsApp / Notifications | 15 000 | 23 |
| Google Maps API | 15 000 | 23 |
| Frais Flutterwave (~1,4 % du CA brut) | ~25 000 | 38 |
| Marketing | 200 000 | 305 |
| Parrainage | 100 000 | 153 |
| Bonus livreurs/relais | 50 000 | 76 |
| Déplacements | 50 000 | 76 |
| Divers | 30 000 | 46 |
| **TOTAL Mois 7-12** | **~860 000** | **~1 312** |

### 10.4 Chemin vers la rentabilité

**Point mort opérationnel** : Le seuil où la commission plateforme couvre les charges mensuelles.

| Période | Charges/mois (XOF) | Livraisons nécessaires/mois | Calcul |
|---|---|---|---|
| Mois 1-6 (solo) | 348 000 | **~2 200** | 348 000 ÷ 158 (marge nette/livraison) |
| Mois 7-12 (+2 employés) | 860 000 | **~5 450** | 860 000 ÷ 158 |

Avec les projections du tableau ci-dessus :
- **Le point mort "solo"** (~2 200 livraisons/mois) n'est **pas atteint avant le mois 7** (on passe de 700 à 950 livraisons entre M6 et M7) — mais les charges sont si faibles que le déficit mensuel reste gérable (~222 000 XOF au mois 6, soit ~339 EUR)
- **Le point mort "équipe de 3"** (~5 450 livraisons/mois) est atteignable en **année 2** (entre mois 14 et 18 si la croissance se maintient à +15 %/mois)

**Pourquoi le modèle fonctionne malgré un point mort tardif** :
1. Les charges sont **ultra-faibles** — pas de salaires les 6 premiers mois, cloud quasi gratuit, app déjà développée
2. Le déficit total sur 12 mois n'est que de **4 233 000 XOF** (~6 465 EUR), largement couvert par le capital de 10 000 EUR
3. Chaque nouveau relais recruté génère du volume local (effet boule de neige)
4. Les suppléments (express ×1,30, nuit ×1,20, poids) augmentent le panier moyen au-delà de 1 200 XOF
5. Les e-commerçants Instagram/WhatsApp apportent du volume récurrent et prévisible

**Horizon de rentabilité mensuelle estimé** : **Mois 14-18** (avec l'équipe de 3).

### 10.5 Évolution de la trésorerie mois par mois

| Mois | Commissions cumulées (XOF) | Charges cumulées (XOF) | Trésorerie (capital + revenus - charges) |
|---|---|---|---|
| 0 | 0 | 0 | 6 550 000 (capital initial) |
| 1 | 18 000 | 348 000 | 6 220 000 |
| 3 | 84 600 | 1 044 000 | 5 590 600 |
| 6 | 360 000 | 2 088 000 | 4 822 000 |
| 9 | 1 017 000 | 4 668 000 | 2 899 000 |
| 12 | 2 205 000 | 7 248 000 | **1 507 000** |

> La trésorerie reste **toujours positive** sur les 12 mois. À la fin de l'année 1, il reste ~1 507 000 XOF (~2 300 EUR) de trésorerie. Ce coussin permet d'absorber des imprévus ou de prolonger l'exploitation 2-3 mois supplémentaires le temps que le volume atteigne le point mort.

---

## 11. ANALYSE DES RISQUES

### 11.1 Risques opérationnels

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Difficulté à recruter des relais | Moyenne | Élevé | Commission attractive (7,5-15 %), trafic piéton, bonus mensuels |
| Turnover des livreurs | Élevée | Moyen | Gamification, bonus performance, classement, communauté |
| Qualité de service inconsistante | Moyenne | Élevé | Notation 5 étoiles, formation in-app, suspension automatique |
| Perte/vol de colis | Faible | Élevé | Event sourcing, codes PIN, confirmation GPS, assurance optionnelle |

### 11.2 Risques technologiques

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Panne serveur/API | Faible | Élevé | Hébergement Railway (haute dispo), MongoDB Atlas (réplication) |
| Faille de sécurité | Moyenne | Critique | Audit sécurité réalisé (34 points), corrections en cours |
| Dépendance API tierces (Google Maps, Flutterwave) | Faible | Moyen | Fallbacks implémentés (Haversine local, calcul offline) |

### 11.3 Risques de marché

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Arrivée d'un concurrent bien financé | Moyenne | Élevé | Avance technologique, réseau relais (barrière à l'entrée), effet réseau |
| Régulation défavorable | Faible | Moyen | Conformité proactive, dialogue avec les autorités |
| Adoption lente du digital | Faible | Moyen | UX simplifiée, support WhatsApp, formation terrain |

### 11.4 Risques financiers

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Cash burn plus rapide que prévu | Faible | Moyen | Structure de coûts ultra-légère (solo 6 mois, ~350K XOF/mois), pas de salaires fixes au départ |
| Trésorerie insuffisante avant point mort | Faible | Moyen | Runway de 12 mois avec 10 000 EUR même sans revenus ; les commissions réduisent le burn dès le mois 1 |
| Fraude paiement | Faible | Moyen | Vérification webhook Flutterwave, idempotence, audit trail |

---

## 12. FEUILLE DE ROUTE ET JALONS

### Phase 1 — Lancement solo (Mois 1-3)

| Jalon | Objectif | KPI |
|---|---|---|
| Recrutement relais | 25 relais actifs à Dakar | Taux d'activation : 80 % |
| Recrutement livreurs | 12 livreurs actifs | Au moins 2 livraisons/livreur/semaine |
| Lancement app (Android) | Publication Google Play Store | 500 téléchargements |
| Premières livraisons | 100 livraisons le 1er mois, 200 au mois 3 | Taux de réussite : 85 %+ |
| Support client | Réponse WhatsApp < 1h (fondateur seul) | Satisfaction : 4/5 |
| Offres de lancement | 200 premières livraisons gratuites distribuées | Taux de conversion en client récurrent : 30 %+ |

### Phase 2 — Croissance organique (Mois 4-6)

| Jalon | Objectif | KPI |
|---|---|---|
| 50 relais actifs | Couverture des quartiers denses de Dakar | 1 relais / 3 km |
| 25 livreurs | Capacité de 30+ livraisons/jour | Délai moyen : < 4h |
| Partenariats e-commerçants | 10-20 vendeurs Instagram/WhatsApp | 20 % du volume |
| Parrainage actif | 500+ parrainages réalisés | CAC < 1 000 XOF/client |
| Décision recrutement | Si > 1 500 livraisons/mois → recruter 2 personnes | Volume + rétention |

### Phase 3 — Structuration (Mois 7-12)

| Jalon | Objectif | KPI |
|---|---|---|
| 100 relais | Tous les grands quartiers de Dakar couverts | 2 500 livraisons/mois |
| 50 livreurs | Flotte stable et fidélisée | Turnover < 20 %/mois |
| Lancement iOS | Publication App Store | 2 000 téléchargements cumulés |
| 50 e-commerçants partenaires | Intégrés via WhatsApp ou API simple | 30 % du volume |
| Point mort solo atteint | Commission > charges (mode fondateur seul) | Rentabilité opérationnelle |

### Vision à 2-3 ans

- **Année 2** : 150+ relais à Dakar, 5 000+ livraisons/mois, rentabilité confirmée, expansion vers Thiès et Mbour. Équipe de 5-8 personnes.
- **Année 3** : Couverture des principales villes du Sénégal. Exploration sous-régionale (Côte d'Ivoire, Mali). 15 000+ livraisons/mois. Levée de fonds si expansion internationale.

---

## 13. ANNEXES

### Annexe A — Glossaire

| Terme | Définition |
|---|---|
| **XOF** | Franc CFA (BCEAO), monnaie du Sénégal. 1 EUR ≈ 655 XOF |
| **Wave** | Service de mobile money dominant au Sénégal (~60 % de part de marché) |
| **Orange Money** | Service de mobile money d'Orange (~30 % de part de marché) |
| **Free Money** | Service de mobile money de Free (Tigo) |
| **Jakartaman** | Coursier moto informel au Sénégal |
| **OTP** | One-Time Password — code de vérification envoyé par SMS |
| **Haversine** | Formule de calcul de distance entre deux points GPS |
| **Event sourcing** | Pattern architectural où chaque changement d'état est un événement immutable |

### Annexe B — Calcul de prix — Exemples concrets (livraisons courantes intra-Dakar)

**Exemple 1 : Relais → Relais, 3 km, 1 kg** (le cas le plus fréquent)
- Base : 700 XOF
- Distance : 3 × 100 = 300 XOF
- Poids : 0 (< 2 kg gratuit)
- **Total : 1 000 XOF**
- Répartition : Plateforme 150, Livreur 700, Relais A 75, Relais B 75

**Exemple 2 : Domicile → Relais, 4 km, 1,5 kg**
- Base : 900 XOF
- Distance : 4 × 100 = 400 XOF
- Poids : 0 (< 2 kg gratuit)
- **Total : 1 300 XOF**
- Répartition : Plateforme 195, Livreur 910, Relais destination 195

**Exemple 3 : Relais → Domicile express, 4 km, 1 kg**
- Base : 1 100 XOF
- Distance : 4 × 100 = 400 XOF
- Sous-total : 1 500 XOF
- Express × 1,30 = 1 950 XOF → arrondi **1 950 XOF**
- Répartition : Plateforme 293, Livreur 1 365, Relais origine 293

**Exemple 4 : Relais → Relais, 5 km, 1 kg, client Argent (-10 %)**
- Base + distance : 700 + 500 = 1 200 XOF
- Réduction Argent : -120 XOF
- **Total : 1 100 XOF** (arrondi 1 100)
- Répartition : Plateforme 165, Livreur 770, Relais A 83, Relais B 83
- Total : 1 120 XOF → arrondi 1 150 XOF
- Répartition : Plateforme 173, Livreur 805, Relais 173

### Annexe C — Références

- McKinsey & Company, "E-commerce in Africa: $75bn opportunity", 2024
- ARTP Sénégal, Rapport annuel sur le marché des télécommunications, 2025
- Jumia, "E-commerce Index Sénégal", 2024
- Banque Mondiale, "Doing Business in Senegal", 2025
- ANSD (Agence Nationale de la Statistique et de la Démographie), Recensement 2023

### Annexe D — Contacts

- **Site web** : pickupoint.sn / denkma.sn
- **API Production** : https://pickupoint-production.up.railway.app
- **Email** : contact@denkma.sn
- **WhatsApp** : +221 XX XXX XX XX

---

*Document confidentiel — Denkma © 2026. Tous droits réservés.*
