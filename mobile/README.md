# PickuPoint Mobile

Application Flutter du projet PickuPoint.

## Démarrage rapide

Lancer l'application en pointant vers une API locale :

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

## Flags utiles

Les notifications push sont désactivées par défaut tant que Firebase n'est pas configuré.

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8001 \
  --dart-define=ENABLE_PUSH_NOTIFICATIONS=false
```

## Notes

- Sans `API_BASE_URL`, l'application utilise l'API Railway de production.
- Tant que Firebase n'est pas branché, laisser `ENABLE_PUSH_NOTIFICATIONS=false`.
- Le flow OTP peut fonctionner en mode mock côté backend si `OTP_PROVIDER=mock`.
