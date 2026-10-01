# Notifications de courses disponibles

## Destination au moment de l’appui

Une notification de nouvelle course ou de rappel lance une vérification, et non
une ouverture aveugle de sa référence. Le même fonctionnement s’applique aux
notifications du téléphone et à celles de la boîte de réception Denkma.

1. Attendre l’autorisation de localisation et une position disponible.
2. Actualiser les missions du livreur. Si une mission est active, ouvrir
   « Mes missions » et ne proposer aucune autre course.
3. Actualiser les courses disponibles pour la position capturée.
4. Plusieurs courses : ouvrir « Disponibles » sans aperçu automatique.
5. Une course : ouvrir son aperçu, même si l’ancienne notification désigne une
   autre course.
6. Aucune course : afficher la liste vide et un message explicite.

Le cache n’est pas utilisé pour prendre cette décision. Une erreur réseau reste
une erreur, avec une action « Réessayer », et n’est pas présentée comme une liste
vide. Chaque nouvel appui relance la vérification, y compris sur la même
notification. Il annule l’effet d’une vérification précédente encore en cours
et ferme son éventuel aperçu automatique. Quitter l’écran empêche toute ouverture
différée sur un autre écran.

## Aucun nouvel appel pendant une mission active

Les statuts `assigned`, `in_progress` et `incident_reported` bloquent les
notifications `mission_available` : nouvelles propositions, vagues de dispatch,
propositions administrateur et rappels. Ce contrôle ne dépend pas uniquement du
bouton « Disponible », qui reste activé pendant une course.

Le serveur exclut les livreurs occupés de la sélection par proximité et de
l’entrée dans un rayon. Il revérifie leur mission active avant de stocker une
nouvelle notification, puis juste avant l’envoi push. Une proposition bloquée
ne consomme pas le délai de rappel. Un index `(driver_id, status)` accélère ces
contrôles. L’application ignore aussi une proposition reçue au premier plan si
ses missions chargées indiquent déjà une course active.

Les messages et rappels nécessaires à la mission actuelle restent envoyés. Les
propositions peuvent reprendre après sa fin, son annulation ou son échec, sous
réserve de la disponibilité, des règles de proximité et du délai de rappel.
Une notification déjà envoyée avant l’acceptation peut encore être présente sur
le téléphone ; son ouverture revérifie la mission active.

## Déploiement

Le filtrage des destinataires nécessite le déploiement backend. La navigation
actualisée nécessite la mise à jour Dart de l’application. Aucun plugin, fichier
natif, dépendance ou asset mobile n’est modifié pour ces changements.
