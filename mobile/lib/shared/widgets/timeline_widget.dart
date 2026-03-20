import 'package:flutter/material.dart';
import '../../core/models/parcel.dart';
import '../utils/date_format.dart';
import 'parcel_status_badge.dart';

class TimelineWidget extends StatelessWidget {
  const TimelineWidget({super.key, required this.events});
  final List<ParcelEvent> events;

  @override
  Widget build(BuildContext context) {
    // Trier du plus récent au plus ancien
    final sortedEvents = List<ParcelEvent>.from(events)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (sortedEvents.isEmpty) {
      return const Center(child: Text('Aucun événement enregistré'));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedEvents.length,
      itemBuilder: (context, index) {
        final event = sortedEvents[index];
        final isLast = index == sortedEvents.length - 1;

        return IntrinsicHeight(
          child: Row(
            children: [
              // Indicateur Timeline
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: index == 0 ? Theme.of(context).primaryColor : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Colors.grey.shade300,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Détails Event
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ParcelStatusBadge(status: event.status),
                          Text(
                            formatDate(event.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (event.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            event.note!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
