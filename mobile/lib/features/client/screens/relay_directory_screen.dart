import 'package:flutter/material.dart';

import '../widgets/relay_selector_modal.dart';

class RelayDirectoryScreen extends StatelessWidget {
  const RelayDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Points relais')),
      body: const SafeArea(
        child: RelaySelectorModal(consultative: true),
      ),
    );
  }
}
