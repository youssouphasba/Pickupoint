import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/api/api_endpoints.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/features/admin/screens/admin_whatsapp_support_screen.dart';
import 'package:pickupoint/shared/widgets/support_whatsapp_tile.dart';

class SupportApi extends ApiClient {
  int reads = 0;
  int voiceSends = 0;
  int sends = 0;
  String? recipient;
  String? sentText;
  String? requestId;
  bool closed = false;

  Response response(dynamic data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/test'));
  Map<String, dynamic> conversation(String id) => {
        'conversation_id': id,
        'phone': id == 'wa_one' ? '+221771111111' : '+221772222222',
        'matched_user': {'name': id == 'wa_one' ? 'Awa' : 'Moussa'},
        'status': 'open',
        'can_reply_freeform': !closed,
        'reply_window_expires_at': DateTime.now()
            .add(Duration(hours: closed ? -1 : 1))
            .toIso8601String(),
      };
  @override
  Future<Response> getWhatsappSupportConversations(
          {String? status,
          String? query,
          int limit = 50,
          int skip = 0}) async =>
      response({
        'conversations': [conversation('wa_one'), conversation('wa_two')],
        'total': 2
      });
  @override
  Future<Response> getWhatsappSupportConversation(String id,
      {String? before}) async {
    reads++;
    return response({
      'conversation': conversation(id),
      'messages': [
        {
          'message_id': before == null ? 'recent-$id' : 'older-$id',
          'direction': 'outbound',
          'text': before == null ? 'Réponse récente' : 'Ancien message',
          'delivery_status': 'delivered',
          'created_at': DateTime.now()
              .subtract(Duration(hours: before == null ? 0 : 1))
              .toIso8601String(),
        }
      ],
      'has_more': before == null,
      'next_before': before == null ? 'recent-$id' : null,
      'notes': [
        {
          'note_id': 'note',
          'text': 'Note réservée aux admins',
          'admin_name': 'Admin'
        }
      ]
    });
  }

  @override
  Future<Response> getWhatsappSupportSettings() async => response({
        'quick_replies': [
          {'label': 'Code colis', 'text': 'Votre code de suivi ?'}
        ]
      });
  @override
  Future<Response> sendWhatsappSupportTextReply(String id, String text,
      {String? requestId}) async {
    sends++;
    recipient = id;
    sentText = text;
    this.requestId = requestId;
    return response({
      'message': {'delivery_status': 'accepted'}
    });
  }

  @override
  Future<Response> sendWhatsappSupportVoiceReply(String id, String filePath,
      {String? requestId}) async {
    voiceSends++;
    recipient = id;
    this.requestId = requestId;
    return response({
      'message': {'delivery_status': 'accepted'}
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  String? recordingPath;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('denkma-support-test-');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => directory.path);
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events'
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null);
        }
        return null;
      });
    }
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'), (call) async {
      if (call.method == 'hasPermission' ||
          call.method == 'isEncoderSupported') {
        return true;
      }
      if (call.method == 'create') {
        final id = (call.arguments as Map)['recorderId'];
        messenger.setMockMethodCallHandler(
            MethodChannel('com.llfbandit.record/events/$id'),
            (_) async => null);
      }
      if (call.method == 'start') {
        recordingPath = (call.arguments as Map)['path'] as String;
      }
      if (call.method == 'stop') return recordingPath;
      return null;
    });
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, SupportApi api) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: AdminWhatsappSupportScreen())));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text).first, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  test('les identifiants historiques avec + sont encodés', () {
    expect(ApiEndpoints.adminWhatsappSupportConversation('wa_+221'),
        contains('wa_%2B221'));
  });
  testWidgets('support masqué sans contact configuré', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          supportWhatsAppProvider
              .overrideWith((ref) async => {'url': '', 'phone': ''})
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SupportWhatsAppTile(trackingCode: 'PKP-TEST')))));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });
  testWidgets(
      'statuts détaillés, notes privées et accusé de livraison visibles',
      (tester) async {
    await show(tester, SupportApi());
    expect(find.text('Action interne'), findsWidgets);
    await reveal(tester, 'Livré');
    expect(find.text('Livré'), findsOneWidget);
    await reveal(tester, 'Note réservée aux admins');
    expect(find.text('Notes internes'), findsOneWidget);
    await close(tester);
  });
  testWidgets('messages précédents accessibles sans perdre les derniers',
      (tester) async {
    await show(tester, SupportApi());
    await reveal(tester, 'Messages précédents');
    await tester.tap(find.text('Messages précédents'));
    await tester.pumpAndSettle();
    expect(find.text('Ancien message'), findsOneWidget);
    expect(find.text('Réponse récente'), findsOneWidget);
    await close(tester);
  });
  testWidgets('réponse rapide seulement préremplie puis envoi explicite',
      (tester) async {
    final api = SupportApi();
    await show(tester, api);
    await reveal(tester, 'Code colis');
    await tester.tap(find.text('Code colis'));
    await tester.pumpAndSettle();
    expect(api.sends, 0);
    await reveal(tester, 'Envoyer le texte');
    await tester.tap(find.text('Envoyer le texte'));
    await tester.pumpAndSettle();
    expect(api.sentText, 'Votre code de suivi ?');
    expect(api.recipient, 'wa_one');
    expect(api.requestId, isNotNull);
    await close(tester);
  });
  testWidgets(
      'vocal préécoutable sans envoi automatique et destinataire verrouillé',
      (tester) async {
    final api = SupportApi();
    await show(tester, api);
    await reveal(tester, 'Enregistrer un vocal');
    await tester.tap(find.text('Enregistrer un vocal'));
    await tester.pumpAndSettle();
    expect(find.text('Arrêter pour écouter'), findsOneWidget);
    await tester.tap(find.text('Arrêter pour écouter'));
    await tester.pumpAndSettle();
    expect(api.voiceSends, 0);
    expect(find.text('Vocal enregistré — non envoyé'), findsOneWidget);
    await reveal(tester, 'Envoyer le vocal');
    await tester.runAsync(() async {
      await tester.tap(find.text('Envoyer le vocal'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(api.voiceSends, 1);
    expect(api.recipient, 'wa_one');
    await close(tester);
  });
  testWidgets('expiration interdit les réponses libres', (tester) async {
    final api = SupportApi()..closed = true;
    await show(tester, api);
    expect(find.text('Envoyer le texte'), findsNothing);
    await reveal(tester, 'Envoyer une relance approuvée');
    expect(find.text('Envoyer une relance approuvée'), findsOneWidget);
    await close(tester);
  });
  testWidgets('la conversation active est actualisée automatiquement',
      (tester) async {
    final api = SupportApi();
    await show(tester, api);
    final initial = api.reads;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(api.reads, greaterThan(initial));
    await close(tester);
  });
}
