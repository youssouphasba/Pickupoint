import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';

void main() {
  test('Generic and empty labels do not hide a real city', () {
    final mission = DeliveryMission.fromJson({
      'created_at': '2026-09-15T00:00:00Z',
      'pickup_area_label': 'Position expéditeur',
      'pickup_city': 'Paris',
      'delivery_area_label': '',
      'delivery_city': '',
      'delivery_label': 'Adresse destinataire',
    });
    expect(mission.pickupAreaLabel, 'Paris');
    expect(mission.deliveryAreaLabel, 'Quartier indisponible');
  });
}
