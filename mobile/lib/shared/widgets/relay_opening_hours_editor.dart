import 'package:flutter/material.dart';

const relayWeekDays = <Map<String, String>>[
  {'key': 'monday', 'label': 'Lundi'},
  {'key': 'tuesday', 'label': 'Mardi'},
  {'key': 'wednesday', 'label': 'Mercredi'},
  {'key': 'thursday', 'label': 'Jeudi'},
  {'key': 'friday', 'label': 'Vendredi'},
  {'key': 'saturday', 'label': 'Samedi'},
  {'key': 'sunday', 'label': 'Dimanche'},
];

Map<String, dynamic> normalizeRelayOpeningHours(dynamic value) {
  final result = <String, dynamic>{
    for (final day in relayWeekDays)
      day['key']!: {
        'enabled': false,
        'open': '08:00',
        'close': '20:00',
      },
  };
  if (value is String) {
    final range = RegExp(
      r'(\d{1,2}(?:(?::|h)\d{0,2})?)\s*[-–]\s*(\d{1,2}(?:(?::|h)\d{0,2})?)',
      caseSensitive: false,
    ).firstMatch(value);
    if (range != null) {
      final open = _normalizeTime(range.group(1)!);
      final close = _normalizeTime(range.group(2)!);
      final lower = value.toLowerCase();
      final count = RegExp(r'lun\s*[-–]\s*sam').hasMatch(lower)
          ? 6
          : RegExp(r'lun\s*[-–]\s*ven').hasMatch(lower)
              ? 5
              : 7;
      for (final day in relayWeekDays.take(count)) {
        result[day['key']!] = {'enabled': true, 'open': open, 'close': close};
      }
    }
    return result;
  }
  if (value is! Map) return result;
  final general = value['general'];
  if (general is String) {
    final legacy = normalizeRelayOpeningHours(general);
    for (final day in relayWeekDays) {
      final key = day['key']!;
      result[key] = legacy[key];
    }
  }
  for (final day in relayWeekDays) {
    final raw = value[day['key']];
    if (raw is Map) {
      result[day['key']!] = {
        'enabled': raw['enabled'] != false &&
            raw['open'] != null &&
            raw['close'] != null,
        'open': raw['open']?.toString() ?? '08:00',
        'close': raw['close']?.toString() ?? '20:00',
      };
    }
  }
  return result;
}

String _normalizeTime(String value) {
  var clean = value.trim().toLowerCase().replaceFirst('h', ':');
  if (!clean.contains(':')) clean = '$clean:00';
  if (clean.endsWith(':')) clean = '${clean}00';
  final parts = clean.split(':');
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}

String relayOpeningHoursSummary(dynamic value) {
  final hours = normalizeRelayOpeningHours(value);
  final entries = <String>[];
  for (final day in relayWeekDays) {
    final entry = hours[day['key']] as Map<String, dynamic>;
    if (entry['enabled'] == true) {
      entries.add(
          '${day['label']!.substring(0, 3)} ${entry['open']}–${entry['close']}');
    }
  }
  return entries.isEmpty ? 'Fermé tous les jours' : entries.join(' · ');
}

List<String> relayOpeningHoursLines(dynamic value) {
  final hours = normalizeRelayOpeningHours(value);
  return [
    for (final day in relayWeekDays)
      '${day['label']}: ${hours[day['key']]['enabled'] == true ? '${hours[day['key']]['open']}–${hours[day['key']]['close']}' : 'Fermé'}',
  ];
}

class RelayOpeningHoursEditor extends StatelessWidget {
  const RelayOpeningHoursEditor(
      {super.key, required this.value, required this.onChanged});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;

  Future<void> _pickTime(BuildContext context, String day, String field) async {
    final entry = Map<String, dynamic>.from(value[day] ?? {});
    final parsed = _timeOfDay(entry[field]?.toString()) ??
        const TimeOfDay(hour: 8, minute: 0);
    final selected =
        await showTimePicker(context: context, initialTime: parsed);
    if (selected == null) return;
    onChanged({
      ...value,
      day: {
        ...entry,
        field:
            '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}'
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Jours et horaires d’ouverture',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Un jour non sélectionné sera affiché comme fermé.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 8),
        ...relayWeekDays.map((day) {
          final key = day['key']!;
          final entry = Map<String, dynamic>.from(value[key] ?? {});
          final enabled = entry['enabled'] == true;
          return LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final dayWidth = 128 * textScale;
            final daySelector = CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(day['label']!,
                  softWrap: false, style: const TextStyle(fontSize: 13)),
              value: enabled,
              onChanged: (checked) => onChanged({
                ...value,
                key: {...entry, 'enabled': checked == true}
              }),
            );
            final times = Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      enabled ? () => _pickTime(context, key, 'open') : null,
                  child: Text(entry['open']?.toString() ?? '08:00'),
                ),
              ),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('à')),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      enabled ? () => _pickTime(context, key, 'close') : null,
                  child: Text(entry['close']?.toString() ?? '20:00'),
                ),
              ),
            ]);
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: constraints.maxWidth < dayWidth + 200 * textScale
                    ? Column(children: [daySelector, times])
                    : Row(children: [
                        SizedBox(width: dayWidth, child: daySelector),
                        Expanded(child: times),
                      ]));
          });
        }),
      ],
    );
  }
}

TimeOfDay? _timeOfDay(String? value) {
  final parts = value?.split(':');
  if (parts == null || parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}
