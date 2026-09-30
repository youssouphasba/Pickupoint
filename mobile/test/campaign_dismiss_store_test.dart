import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/promotions/campaign_dismiss_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('fermetures persistantes et isolées par compte', () async {
    await CampaignDismissStore.dismiss('user', 'campaign');
    expect(await CampaignDismissStore.read('user'), {'campaign'});
    expect(await CampaignDismissStore.read('other'), isEmpty);
    expect(
        await const FlutterSecureStorage()
            .read(key: 'campaign_dismissals:user'),
        contains('campaign'));
  });

  test('fermetures simultanées ne se remplacent pas', () async {
    await Future.wait([
      CampaignDismissStore.dismiss('user', 'first'),
      CampaignDismissStore.dismiss('user', 'second'),
      CampaignDismissStore.dismiss('user', 'first'),
    ]);
    expect(await CampaignDismissStore.read('user'), {'first', 'second'});
  });

  test('une valeur corrompue est réparable', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'campaign_dismissals:user': '{invalid'});
    expect(await CampaignDismissStore.read('user'), isEmpty);
    await CampaignDismissStore.dismiss('user', 'new');
    expect(await CampaignDismissStore.read('user'), {'new'});
  });
}
