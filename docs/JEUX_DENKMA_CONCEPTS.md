# Jeux Denkma — concepts à reprendre

Dernière mise à jour : 5 octobre 2026.

Statut : idées conservées pour une prochaine séance de conception. Cette note ne lance aucun développement, aucune publication ni aucun rappel automatique. Les noms, paramètres et exemples restent à affiner.

L'[architecture de référence de Denkma Manager](DENKMA_MANAGER_ARCHITECTURE.md), rédigée le 5 octobre 2026, précise les modèles, règles de cohérence, interfaces et lots d'implémentation. Elle fait référence pour les mécanismes techniques détaillés ci-dessous. Les chiffres de la maquette ne constituent pas des règles de production.

## 1. Le colis mystère du jour

### Principe

Une énigme quotidienne : le joueur découvre un objet caché dans une boîte à l'aide d'indices progressifs. L'écran indique clairement « Jeu — aucun colis réel ».

### Parcours envisagé

1. Découvrir la boîte et son premier indice.
2. Proposer une réponse ou demander un indice supplémentaire.
3. Trouver l'objet, puis voir la boîte s'ouvrir avec une animation.
4. Obtenir une illustration ou un tampon dans son album de découvertes.

Pour une première version, les réponses à choisir parmi quelques propositions faciliteraient l'accès et éviteraient les refus liés à l'orthographe. Une mauvaise réponse déclencherait un encouragement. Aucun chronomètre obligatoire.

### Progression

- Collections thématiques : quotidien, cuisine, voyages, Sénégal et objets insolites.
- Album personnel d'objets découverts.
- Badges de découverte et de collection ; certains peuvent valoriser une résolution avec peu d'indices.
- Surprises visuelles sans versement d'argent ; des avantages de fidélité peuvent compléter la progression selon les règles à définir ci-dessous.
- Partage facultatif du résultat sans dévoiler la réponse.
- Accès aux anciennes énigmes en mode découverte ; manquer un jour ne détruit pas la collection.

### Première version envisagée

Une énigme quotidienne, des indices progressifs, une ouverture animée et un album. Les classements et défis entre amis seraient étudiés ultérieurement selon l'intérêt réel des utilisateurs.

## 2. Tri Express, évoluant vers Denkma Manager

### Vision retenue

L'idée initiale de tri de colis devient une simulation d'entreprise de livraison. Le joueur développe un réseau, organise les transports, traite les incidents, peut gagner ou perdre des crédits virtuels et doit respecter ses engagements.

« Denkma Manager » est un nom de travail. « Tri Express » pourrait désigner l'activité de tri à l'intérieur de cette simulation.

Une entreprise persistante appartient au compte et reste la même entre appareils ou changements de rôle. Le serveur fait progresser la simulation ; la scène animée en représente l'état. Colis, employés, relais et trajets sont fictifs.

### Boucle de jeu

Organiser → livrer → gagner → investir → gérer les imprévus.

Le joueur commence avec un petit local, un moyen de transport et quelques clients fictifs. Il peut ensuite recruter du personnel fictif, acheter ou louer des véhicules, agrandir le centre de tri, ouvrir des relais et des zones, et obtenir des contrats commerciaux.

### Gestion de l'équipe

Le recrutement, les affectations, les salaires, la formation et les départs font partie de la gestion de l'entreprise. Une rubrique « Équipe » regroupe ces décisions et leur impact sur les opérations. Tous les employés sont fictifs, sans lien avec les comptes des vrais livreurs ou responsables de relais.

#### Recrutement et rôles

- Livreurs : assurent les tournées, selon leurs compétences, leur disponibilité et les véhicules qu'ils peuvent utiliser.
- Agents de tri : réceptionnent, trient et préparent les colis ; leur capacité influence les files d'attente au dépôt.
- Mécaniciens : entretiennent et réparent les véhicules ; leur disponibilité influence les immobilisations.
- Responsables de dépôt : coordonnent l'équipe et les départs ; leurs compétences peuvent améliorer l'organisation lorsque le réseau grandit.

Chaque candidat présente son expérience, ses compétences, sa capacité de travail, son salaire demandé et les éventuels coûts d'embauche ou de formation initiale. Avant confirmation, afficher le coût immédiat, les charges récurrentes et l'effet attendu sur la capacité de l'entreprise. Les rôles et leur accès peuvent évoluer avec la progression ; leurs paramètres restent configurables, sans montant ou seuil fixé dans cette note.

#### Affectations et conditions de travail

Le joueur affecte les employés aux dépôts, véhicules, tournées et horaires compatibles avec leurs compétences. Acheter un véhicule sans livreur disponible ne crée pas une capacité de livraison supplémentaire. De même, recruter un livreur n'accélère pas un tri déjà saturé.

Un employé ou un véhicule ne peut pas être affecté simultanément à des opérations incompatibles. Les temps de travail, de déplacement, de repos et de formation doivent être pris en compte dans la disponibilité réelle de l'équipe fictive.

Prévoir fatigue, motivation, progression des compétences, repos et absences. La surcharge peut augmenter les erreurs, dommages et retards ; la formation améliore les compétences mais mobilise temporairement l'employé. Les effets et avertissements doivent rester compréhensibles, proportionnés et adaptés à la difficulté.

#### Salaires et trésorerie

Les salaires sont des charges récurrentes en crédits fictifs, avec une périodicité et des échéances explicites. La fiche de l'équipe et la prévision de trésorerie distinguent les coûts d'embauche, la masse salariale, les montants déjà payés et les échéances à venir. Les salaires et les autres coûts du personnel entrent dans le bénéfice net de la période concernée.

Une charge acquise mais non encore payée ne doit pas être confondue avec une sortie de trésorerie. Son paiement réduit la trésorerie sans comptabiliser la même charge une seconde fois. Une échéance déjà traitée ne peut pas être débitée à nouveau lors d'une reconnexion ou d'un rattrapage du temps simulé.

Les charges suivent le temps simulé, y compris pendant les absences du joueur, sans exiger une connexion pour valider chaque salaire. Prévoir un règlement automatique lorsque les crédits sont suffisants et des avertissements en amont lorsque la trésorerie prévue devient insuffisante. Les retards de salaire peuvent affecter la motivation et la disponibilité, puis entraîner un départ selon des règles annoncées ; ils ne créent aucune dette réelle.

Le rattrapage des absences prolongées, les périodes de grâce et les plafonds de pertes suivent les règles de protection de l'entreprise. Une pause fige simultanément les salaires, opérations et revenus futurs ; les charges déjà acquises restent enregistrées. Ses conditions et les reprises sont définies dans l'architecture de référence.

#### Départs et licenciements

Le joueur peut licencier un employé ; celui-ci peut également démissionner selon les événements et règles du jeu. Avant un licenciement, demander une confirmation et présenter les éventuels coûts de départ fictifs, l'économie future de salaire, la perte de capacité et les engagements menacés.

Ne pas supprimer un employé d'une tournée active sans gérer la transition. Définir une date de départ compatible avec les opérations engagées ou organiser un remplacement. Les colis, réparations et tâches non terminées restent suivis et doivent être réaffectés ; les opérations déjà réalisées et l'historique de leurs coûts sont conservés. Un départ ne remet pas les échéances des colis à zéro.

Le coût de départ et la dernière période de salaire doivent être calculés et enregistrés une seule fois. Aucune nouvelle charge salariale ne doit courir au-delà de la date de fin effective, sauf une obligation fictive explicitement présentée dans les règles du jeu.

#### Accompagnement par l'Expert Denkma

Le conseiller compare recrutement, réaffectation, formation et réduction d'effectif à partir de la charge de travail, des capacités, des compétences et de la trésorerie prévisionnelle. Il explique les coûts, les gains estimés et les risques opérationnels avant de recommander une décision ; le joueur reste libre de son choix.

Exemple : « Votre dépôt est saturé, mais vos véhicules restent disponibles. Recruter un agent de tri serait plus utile qu'un livreur supplémentaire. » Le conseil doit dépendre de la situation réelle de la simulation, pas être une réponse fixe.

Les salaires, pertes et décisions de personnel restent entièrement internes au jeu. Ils ne modifient pas le solde Denkma réel ni les avantages de fidélité déjà acquis.

### Décisions et conséquences

Les colis ont une destination, une priorité, un volume et éventuellement une contrainte de manutention ou de remise. Le joueur décide des regroupements, parcours et départs.

Attendre peut améliorer le remplissage d'un véhicule, mais compromettre une échéance. Les stratégies possibles comprennent le service local, les tournées régionales groupées et les contrats exigeant davantage de fiabilité.

Événements envisagés : relais complet, véhicule retardé ou en panne, arrivée d'un colis prioritaire et demande de retrait en relais. Les situations doivent être compréhensibles et laisser une possibilité de réaction.

Les pertes peuvent provenir de transports mal remplis, d'une expansion trop rapide, d'un entretien reporté, d'un dommage ou d'un engagement non tenu. Le joueur doit pouvoir en consulter les causes et les coûts.

### Temps réel et activité quotidienne

Modèle hybride : les opérations déjà organisées continuent entre les connexions. Les tournées, arrivées, travaux et réparations progressent ; un récapitulatif animé présente le résultat au retour. Le moteur serveur traite les échéances dans l'ordre, de façon identique que le joueur reste connecté ou revienne après une absence.

Prévoir une ou deux décisions utiles par jour, regroupables dans une courte session sans heure de connexion imposée : organiser l'activité et maintenir l'entreprise ou traiter un incident.

Distinction essentielle précisée pendant la discussion :

- Un colis affecté à une tournée préparée peut être livré automatiquement en l'absence du joueur.
- Un colis accepté, mais laissé au dépôt sans organisation, continue d'attendre. Son échéance peut être dépassée même si le joueur ne se connecte pas.
- Ouvrir le jeu ne remet pas les délais à zéro : il faut une action qui traite réellement la situation.

Un retard peut provoquer une réclamation, une baisse de satisfaction, des pénalités virtuelles, puis une annulation et un retour. Les délais, avertissements, périodes de grâce et impacts sont présentés avant l'engagement et dépendent de la difficulté. Les exemples de délais évoqués ne sont pas des constantes à coder.

Éviter les pertes cumulées sans limite et les remboursements ou annulations comptabilisés plusieurs fois. Une absence prolongée ne doit pas déclencher une destruction disproportionnée de l'entreprise.

Les offres non acceptées ne créent aucune obligation. Les opérations préparées et les paies dues sont traitées automatiquement selon les ressources disponibles ; l'entreprise n'accepte pas de nouveaux contrats en l'absence du joueur dans la première version.

La pause volontaire commence par une phase de clôture des engagements. Une protection automatique fige l'entreprise à une limite d'absence ou de détresse configurée, avec conservation de l'état, des retards et des obligations fictives. À la reprise, délais et charges repartent du temps de simulation conservé ; ouvrir le jeu n'efface pas les conséquences déjà acquises. Les dates réelles des campagnes et bons de fidélité continuent de s'appliquer pendant une pause du jeu.

### Expert Denkma

Le joueur peut consulter un conseiller du jeu qui compare ses options pour améliorer les gains virtuels ou limiter les pertes.

- Débutant : accompagnement et avertissements fréquents.
- Intermédiaire : interventions sur les décisions importantes.
- Expert : consultation principalement à la demande.

Une recommandation explique son raisonnement, les coûts, gains estimés, risques et alternatives. Le joueur garde la décision finale et peut demander « Pourquoi ? ».

Les conseils s'appuient sur la simulation : trésorerie, capacités, échéances, coûts, effectifs, compétences, disponibilités et réputation. Les prévisions sont des estimations, pas des gains garantis. Comparer ensuite le résultat à la prévision aiderait le joueur à progresser.

### Univers visuel

Vue isométrique vivante et interactive : tapis de tri, chargements, véhicules en tournée, retours des livreurs fictifs, extensions de bâtiments, incidents visibles, météo et éclairage.

Toucher un colis, un véhicule ou un relais ouvre ses informations et ses actions. Les animations expliquent l'état du réseau et les conséquences d'une décision. Le niveau de réalisme et les performances mobiles restent à tester.

### Six KPI principaux

| KPI | Rôle |
| --- | --- |
| Trésorerie disponible | Crédits virtuels comptabilisés moins engagements déjà réservés ; les obligations exigibles sont indiquées séparément. |
| Bénéfice net | Revenus acquis moins charges de la période, dont salaires et coûts du personnel, pénalités et remboursements, sans double comptabilisation lors du paiement. |
| Livraisons dans les délais | Respect des engagements arrivés à échéance, en conservant les colis non livrés en retard dans le calcul. |
| Colis en retard | Nombre et ancienneté des retards non terminaux à traiter ; les échecs terminaux restent dans l'historique de qualité. |
| Réputation | Confiance des clients, influencée par la qualité, les retards et la résolution des incidents. |
| Remplissage des véhicules | Capacité occupée rapportée à la capacité disponible sur les segments parcourus, à interpréter avec les contraintes de délais. |

Indicateurs détaillés : marge par colis ou contrat, disponibilité et pannes des véhicules, occupation des dépôts et relais, colis endommagés/perdus/annulés, clients réguliers, contrats actifs et pénalités payées. Pour l'équipe : effectifs par rôle, capacité disponible, charge de travail, fatigue et motivation, masse salariale, salaires en attente, formations et départs.

Chaque KPI doit permettre de consulter son évolution, ses causes et les actions proposées. L'expert les analyse ensemble. Trésorerie et bénéfice restent distincts ; un véhicule plein n'est pas une réussite si son départ tardif entraîne des pénalités. Les objectifs et seuils dépendent de la difficulté et de la taille de l'entreprise.

## 3. Récompenses liées au programme de fidélité

### Décision retenue

Les jeux peuvent donner accès à des avantages du programme de fidélité Denkma : bons de réduction, livraisons offertes et autres avantages de service à définir. Aucun gain d'argent réel, versement ou retrait n'est prévu.

Ces avantages doivent s'appuyer sur le programme de fidélité de Denkma, sans créer un deuxième portefeuille ou un système concurrent. Leur mécanisme d'acquisition reste à concevoir et à valider avant toute implémentation.

### Économie fictive et programme de fidélité

- Crédits virtuels de Denkma Manager : servent uniquement à gérer l'entreprise fictive. Ni conversion en FCFA ni conversion automatique des bénéfices du jeu en points de fidélité.
- Points de statut existants : déterminent le niveau de fidélité client et sont conservés. Ils ne sont pas dépensés lors d'un échange contre un bon.
- Points avantages disponibles, à ajouter au même programme de fidélité : peuvent être acquis via des défis ou jalons éligibles, vérifiés côté serveur, puis échangés contre des bons. Le jeu ne possède pas sa propre copie de ce solde. Un échange ne diminue pas le niveau client ; la progression visuelle seule ne constitue pas une preuve d'attribution.
- Avantages utilisables : bons obtenus via la fidélité, non convertibles en argent et non retirables depuis le solde Denkma.

Parcours proposé : défi ou jalon éligible validé → attribution de points avantages → échange contre un bon → application à une livraison réelle éligible. Les conditions exactes et la possibilité de ce parcours restent à valider, notamment pour les règles des boutiques d'applications. Le raccordement détaillé est décrit dans l'architecture ; les points de statut déjà acquis ne sont pas automatiquement dupliqués en points échangeables.

Exemples à étudier : collection thématique terminée dans le colis mystère, objectif de gestion atteint dans Denkma Manager, puis échange des points contre une réduction ou une livraison offerte. Aucun nombre de points, montant, délai ou fréquence n'est arrêté dans cette note.

### Conditions et financement

L'admin doit pouvoir configurer les défis éligibles, les rôles concernés, les points attribués, les plafonds, la fréquence, la durée de validité, les modes et zones de livraison couverts, le montant maximal pris en charge et les possibilités de cumul. Les conditions sont visibles avant l'obtention et l'utilisation du bon ; une modification de campagne ne doit pas altérer rétroactivement les avantages déjà acquis selon leurs conditions initiales.

Une livraison offerte signifie que Denkma finance la part couverte, pas que le livreur ou le relais travaille gratuitement. Le devis et les règlements doivent préserver leurs rémunérations convenues et identifier explicitement le financement promotionnel. Un éventuel reste à payer doit être affiché avant confirmation.

Le bon s'applique au devis d'une nouvelle livraison avant confirmation et paiement. Il ne doit pas provoquer un remboursement ou un second crédit d'une course déjà payée. L'architecture prévoit sa réservation pendant la confirmation et sa consommation dans la transaction de création du colis, quel que soit le payeur. Sa restitution éventuelle après annulation passe par une opération tracée ; les confirmations de paiement ne consomment jamais le bon une seconde fois.

### Protections

- Pas d'achat d'entrées, de tentatives ou de bonus permettant d'obtenir ces avantages réels.
- Attribution des points et utilisation des bons vérifiées côté serveur, avec protection contre les doublons, les rejouements et les comptes abusifs.
- Historique compréhensible dans le programme de fidélité et suivi des attributions, utilisations et coûts promotionnels côté admin.
- Une absence, un retard ou une perte dans l'entreprise fictive affecte le jeu, pas le solde réel ni les avantages de fidélité déjà acquis. Une expiration annoncée d'un bon reste distincte d'une pénalité de jeu.
- Les bons ont une valeur réelle même sans versement d'argent : ne pas considérer cette distinction comme une validation automatique de conformité. Vérifier les règles applicables avant le lancement.

## 4. Garde-fous communs

- Jeux facultatifs et distincts des vraies opérations de livraison.
- Aucun vrai colis, destinataire, parcours ou document personnel utilisé dans les scénarios.
- Crédits de jeu entièrement fictifs, sans conversion en FCFA, sans lien avec le solde Denkma et sans mise d'argent.
- Jeu indisponible pour le livreur pendant une mission réelle active.
- Pour les relais, les opérations réelles restent prioritaires.
- Aucun écran ou notification de jeu ne doit être confondu avec une vraie livraison.
- Pas d'encombrement supplémentaire de l'accueil ou de l'en-tête.
- Contenus, scénarios, calendriers, difficulté et paramètres économiques configurables ; éviter les règles métier codées en dur.
- Pour le colis mystère : prévoir une préparation et une prévisualisation des énigmes côté admin.

## 5. Prochaine séance

S'appuyer sur l'architecture de référence pour équilibrer les paramètres avant publication : économie virtuelle, progression, cadence réelle du jeu, délais, protection contre les pertes prolongées et besoins en personnel. Définir les catalogues, salaires, formations, actifs, objectifs de fidélité et budgets. Affiner ensuite la direction artistique et le raccordement des bons aux vraies commandes, puis suivre les lots d'implémentation et leurs critères de fin.
