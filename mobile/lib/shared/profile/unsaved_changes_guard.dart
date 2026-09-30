import 'package:flutter/material.dart';

Future<bool> confirmDiscardChanges(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text(
            'Voulez-vous revenir sans enregistrer vos modifications ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continuer à modifier')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitter sans enregistrer')),
        ],
      ),
    ) ==
    true;
