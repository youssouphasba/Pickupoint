# Logo de l’en-tête — release 1.0.28+48

`logo_header.png` est le logo fourni, détouré en PNG RGBA avec un fond réellement transparent. Préparation avec l’outil intégré de traitement d’images, sans modification des dépendances ni des fichiers natifs.

Consigne utilisée : retirer seulement le fond noir, conserver la moto, le colis, les mains, les couleurs, les proportions et le texte « DENKMA », avec des contours propres et une transparence réelle.

Le logo est maintenant intégré dans `mobile/assets/logo_header.png`, déclaré dans le `pubspec.yaml` et utilisé par l'en-tête client. Ce dossier conserve la source transparente et les aperçus de validation.

L'intégration est terminée ; aucune copie ni application de patch Git supplémentaire n'est nécessaire.

L’intégration remplace les deux éléments du logo actuel par cette image unique dans l’en-tête client, avec ou sans parrainage. Elle conserve les accès fidélité et les alignements des icônes.

Relancer ensuite l’analyse Flutter et les tests, puis préparer les versions Android et iOS de la nouvelle release. Ne pas appliquer cette intégration dans la source destinée à un patch Shorebird de la version 47 : l’image n’est pas embarquée dans cette release.
