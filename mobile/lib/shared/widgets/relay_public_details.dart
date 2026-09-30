import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/relay_point.dart';
import 'relay_opening_hours_editor.dart';

String relayOpeningLabel(RelayPoint relay) => relay.openingStatusKnown
    ? relay.openingStatusLabel ??
        (relay.isOpen ? 'Ouvert maintenant' : 'Fermé maintenant')
    : 'Horaires à compléter';

class RelayPublicDetails extends StatelessWidget {
  const RelayPublicDetails({super.key, required this.relay, this.distance});

  final RelayPoint relay;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final area = <String>{
      if (relay.district?.trim().isNotEmpty == true) relay.district!.trim(),
      if (relay.city.trim().isNotEmpty) relay.city.trim(),
    }.join(', ');
    final color = !relay.openingStatusKnown
        ? Colors.orange.shade800
        : relay.isOpen
            ? Colors.green
            : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.storefront_outlined),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(relay.name, style: Theme.of(context).textTheme.titleLarge))
      ]),
      const SizedBox(height: 10),
      if (relay.addressLabel.trim().isNotEmpty) Text(relay.addressLabel.trim()),
      if (area.isNotEmpty) Text(area),
      if (relay.phone.trim().isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(relay.phone.trim())),
      const SizedBox(height: 10),
      Text(relayOpeningLabel(relay),
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      if (distance != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Depuis ma position : $distance')),
      const SizedBox(height: 8),
      Text(
          'Places disponibles : ${relay.availableSlots.clamp(0, relay.capacity)}'),
      const SizedBox(height: 16),
      const Text('Horaires d’ouverture',
          style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (relay.openingHours == null || relay.openingHours!.isEmpty)
        const Text('Horaires non renseignés.')
      else
        ...relayOpeningHoursLines(relay.openingHours).map((line) => Padding(
            padding: const EdgeInsets.only(bottom: 4), child: Text(line))),
      if (relay.description?.trim().isNotEmpty == true ||
          relay.addressNotes?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 12),
        const Text('Instructions et accès',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (relay.description?.trim().isNotEmpty == true)
          Text(relay.description!.trim()),
        if (relay.addressNotes?.trim().isNotEmpty == true &&
            relay.addressNotes!.trim() != relay.description?.trim())
          Text(relay.addressNotes!.trim()),
      ],
      if (relay.lat != null && relay.lng != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final url = Uri.https('www.google.com', '/maps/search/',
                {'api': '1', 'query': '${relay.lat},${relay.lng}'});
            try {
              if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
                return;
              }
            } catch (_) {}
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Impossible d’ouvrir la carte.')));
            }
          },
          icon: const Icon(Icons.map_outlined),
          label: const Text('Voir sur la carte'),
        ),
      ],
    ]);
  }
}
