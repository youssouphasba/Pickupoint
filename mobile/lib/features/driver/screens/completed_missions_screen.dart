import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../../shared/utils/error_utils.dart';
import '../providers/driver_provider.dart';
import '../widgets/completed_mission_card.dart';

class CompletedMissionsScreen extends ConsumerWidget {
  const CompletedMissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(completedDriverMissionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Missions terminées')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(completedDriverMissionsProvider.future),
        child: missionsAsync.when(
          data: (missions) {
            if (missions.isEmpty) {
              return const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('Aucune mission terminée')),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
              itemCount: missions.length,
              itemBuilder: (context, index) {
                final delay = index.clamp(0, 6) * 35;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(
                    milliseconds: AppMotion.standard.inMilliseconds + delay,
                  ),
                  curve: AppMotion.standardCurve,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: CompletedMissionCard(mission: missions[index]),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(friendlyError(error))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
