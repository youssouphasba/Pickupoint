# Automatisation Google Play

Ce projet utilise `fastlane supply` pour préparer la fiche Google Play et `codemagic.yaml` pour publier l'AAB.

## Variable sensible requise

Dans Codemagic, ajoute une variable secrète :

`GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`

Valeur : le contenu complet du fichier JSON du compte de service Google Play.

Ajoute cette variable dans le groupe Codemagic déjà utilisé par Android :

`android_signing`

## Commandes utiles

Depuis `mobile` :

```bash
bundle install
bundle exec fastlane android upload_store_listing
bundle exec fastlane android deploy_internal
```

## Ce qui peut être automatisé

- Texte de fiche Google Play.
- Icône haute résolution.
- Captures d'écran.
- Notes de version.
- Upload d'un AAB vers une piste de test.

## Ce qui reste manuel dans Play Console

- Création initiale de l'application.
- Questionnaires de conformité Google.
- Classification du contenu.
- Déclaration de confidentialité des données.
- Public cible et contenus.
- Accès app pour les testeurs ou les examinateurs si Google le demande.
- Validation finale si Google bloque une modification avant examen.
