# pickupoint

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Configuration API

L'URL API peut être injectée au build avec `--dart-define` :

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

Sans valeur fournie, l'app utilise l'API de production Railway par défaut.
