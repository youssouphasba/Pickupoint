# Validation du GPS

## Périmètre

- Client : carte live et notifications de progression avec distance/estimation pour domicile → domicile. En relais → domicile, seul le destinataire y accède après la collecte, sur la mission vers son domicile. Aucun live avant collecte, entre relais, en domicile → relais ou en relais → relais ; les notifications d’étape restent disponibles.
- Admin : positions des livreurs disponibles et des missions actives, tous modes. Le parcours sélectionné charge son historique complet ; le détail du colis conserve la trace réelle de la collecte à la fin de mission.
- Livreur indisponible sans mission : pas de capture continue. Les mises à jour réseau de la liste de missions ne doivent pas interrompre une capture en cours.
- Une position ancienne reste une dernière position connue, pas une position live. Les interruptions GPS ne sont pas reliées par une ligne fictive.

## Déploiement

Déployer le backend avant le mobile et l’admin : politique de qualité GPS, horodatage des mesures, réception de traces différées et endpoint du parcours complet.

Les réglages GPS sont dans `backend/config.py` et peuvent être surchargés par l’environnement. Le mobile charge `/api/geo/location-policy` et garde des valeurs de secours techniques si le réseau est indisponible. Aucun changement de dépendance ou de configuration native n’est nécessaire pour ces corrections.

Les points capturés hors connexion sont conservés dans le stockage sécurisé du téléphone, limités par `GPS_OFFLINE_BUFFER_HOURS`, rattachés au compte livreur et supprimés localement après transmission ou déconnexion. Le serveur les archive sans remplacer la position live et exclut ceux qui sont antérieurs à la collecte ou postérieurs à la fin. Il n’est pas possible de reconstruire des positions que le système n’a jamais capturées.

## Vérification sur appareils réels

1. Android : autorisation « Toujours », position précise, puis disponibilité activée dans l’app ouverte. iOS : position précise et autorisation pendant l’utilisation ou toujours, avec le suivi démarré dans l’app ouverte.
2. Consulter la flotte admin, passer sur une autre application, verrouiller l’écran, parcourir une distance et vérifier les coordonnées et la date de mesure.
3. Répéter en mission pour domicile → domicile et pour chaque mode avec relais. En relais → domicile, vérifier l’absence de carte avant collecte puis son apparition pour le destinataire uniquement après collecte, avec distance/estimation vers le domicile. L’expéditeur ne doit pas avoir accès au live pour ce mode. Vérifier également l’absence de live entre relais et pour domicile → relais et relais → relais.
4. Couper le GPS puis le réactiver. Vérifier l’état du signal, la reprise au retour dans l’application et l’absence de double notification de service GPS.
5. Couper le réseau pendant un déplacement puis le rétablir. Vérifier le marqueur récent et la restitution des points intermédiaires dans l’historique, sans fausse position live ancienne.
6. Collecter puis livrer un colis. Le tracé réel doit commencer à la collecte et finir à la fin de mission ; ouvrir également le détail admin du colis.
7. Modifier une adresse avant collecte, par l’app et par le lien sécurisé : le point cible de la mission doit changer et l’ancien itinéraire être invalidé. Après collecte, l’app ne doit plus proposer cette modification.
8. Refuser le GPS dans le sélecteur de position : aucune coordonnée par défaut ne doit être confirmable sans choix explicite sur la carte, recherche ou favori.
9. Déconnecter le livreur : aucune nouvelle capture professionnelle ni transmission ne doit continuer.

Une application forcée à l’arrêt, les restrictions d’économie d’énergie du constructeur et la suspension par le système ne sont pas équivalentes à un simple passage en arrière-plan. Un redémarrage de service Android n’est pas lancé depuis l’arrière-plan après interruption : il reprend à la prochaine ouverture autorisée. Les tests automatisés ne remplacent pas cette vérification physique.
