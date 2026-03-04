import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/promotion.dart';
import 'package:intl/intl.dart';

class AdminPromotionsScreen extends ConsumerStatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  ConsumerState<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends ConsumerState<AdminPromotionsScreen> {
  @override
  Widget build(BuildContext context) {
    final promosAsync = ref.watch(adminPromotionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Promotions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminPromotionsProvider),
          ),
        ],
      ),
      body: promosAsync.when(
        data: (promos) {
          if (promos.isEmpty) {
            return const Center(child: Text('Aucune promotion active'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: promos.length,
            itemBuilder: (context, index) => _PromoCard(promo: promos[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePromoDialog(context),
        label: const Text('Nouvelle Promo'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showCreatePromoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CreatePromoDialog(),
    ).then((value) {
      if (value == true) ref.invalidate(adminPromotionsProvider);
    });
  }
}

class _PromoCard extends ConsumerWidget {
  const _PromoCard({required this.promo});
  final Promotion promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpired = promo.endDate.isBefore(DateTime.now());
    final color = promo.isActive && !isExpired ? Colors.green : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPromoActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      promo.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Text(
                      promo.isActive ? (isExpired ? 'Expiré' : 'Actif') : 'Désactivé',
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                promo.description,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(icon: Icons.tag, label: promo.promoCode ?? 'Automatique'),
                  const SizedBox(width: 8),
                  _InfoChip(icon: Icons.card_giftcard, label: promo.typeLabel, color: Colors.blue),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Du ${DateFormat('dd/MM').format(promo.startDate)} au ${DateFormat('dd/MM/yyyy').format(promo.endDate)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Utilisations: ${promo.usesCount}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPromoActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(promo.isActive ? Icons.block : Icons.check_circle, 
                  color: promo.isActive ? Colors.orange : Colors.green),
              title: Text(promo.isActive ? 'Désactiver' : 'Activer'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(apiClientProvider).updatePromotion(promo.promoId, {'is_active': !promo.isActive});
                  ref.invalidate(adminPromotionsProvider);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Supprimer?'),
                    content: const Text('Cette action est irréversible.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await ref.read(apiClientProvider).deletePromotion(promo.promoId);
                    ref.invalidate(adminPromotionsProvider);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.color = Colors.grey});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _CreatePromoDialog extends StatefulWidget {
  const _CreatePromoDialog();

  @override
  State<_CreatePromoDialog> createState() => _CreatePromoDialogState();
}

class _CreatePromoDialogState extends State<_CreatePromoDialog> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _desc = '';
  String _type = 'percentage';
  double _value = 10;
  String _target = 'all';
  String? _code;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 30));
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle Promotion'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Titre (interne)'),
                onChanged: (v) => _title = v,
                validator: (v) => v?.isEmpty == true ? 'Requis' : null,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Description client'),
                onChanged: (v) => _desc = v,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'percentage', child: Text('Pourcentage (%)')),
                  DropdownMenuItem(value: 'fixed_amount', child: Text('Montant Fixe (XOF)')),
                  DropdownMenuItem(value: 'free_delivery', child: Text('Livraison Gratuite')),
                  DropdownMenuItem(value: 'express_upgrade', child: Text('Express Offert')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              if (_type == 'percentage' || _type == 'fixed_amount')
                TextFormField(
                  decoration: InputDecoration(labelText: _type == 'percentage' ? 'Valeur (%)' : 'Valeur (XOF)'),
                  keyboardType: TextInputType.number,
                  initialValue: '10',
                  onChanged: (v) => _value = double.tryParse(v) ?? 0,
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _target,
                decoration: const InputDecoration(labelText: 'Cible'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tous les utilisateurs')),
                  DropdownMenuItem(value: 'first_delivery', child: Text('1ère livraison')),
                  DropdownMenuItem(value: 'gold_only', child: Text('Membres GOLD')),
                ],
                onChanged: (v) => setState(() => _target = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Code Promo (vide = AUTO)'),
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) => _code = v,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Date fin'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_end)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final pick = await showDatePicker(
                    context: context, 
                    initialDate: _end, 
                    firstDate: DateTime.now(), 
                    lastDate: DateTime.now().add(const Duration(days: 365))
                  );
                  if (pick != null) setState(() => _end = pick);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
        ),
      ],
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    
    final body = {
      'title': _title,
      'description': _desc,
      'promo_type': _type,
      'value': _value,
      'target': _target,
      'promo_code': _code?.toUpperCase().trim().isEmpty == true ? null : _code?.toUpperCase().trim(),
      'start_date': _start.toIso8601String(),
      'end_date': _end.toIso8601String(),
      'is_active': true,
    };

    try {
      final container = ProviderScope.containerOf(context);
      await container.read(apiClientProvider).createPromotion(body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }
}
