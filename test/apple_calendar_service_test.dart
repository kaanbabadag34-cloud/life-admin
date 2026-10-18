import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/services/apple_calendar_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('life_admin/calendar');
  final calls = <MethodCall>[];
  List<Map<String, String>> listedEvents = [];
  String? currentUser;
  late AppleCalendarService service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    listedEvents = [];
    currentUser = 'user-a';
    service = AppleCalendarService.forTest(userIdProvider: () => currentUser);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);

      switch (call.method) {
        case 'authorizationStatus':
          return 'granted';
        case 'requestAccess':
          return true;
        case 'upsertEvent':
          return 'EV-${(call.arguments as Map)['planId']}';
        case 'deleteEvent':
          return true;
        case 'listOurEvents':
          return listedEvents;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<MethodCall> only(String method) =>
      calls.where((c) => c.method == method).toList();

  final start = DateTime(2026, 10, 21, 15, 0);

  Future<void> sync(String planId, {DateTime? at, int? duration}) {
    return service.syncPlan(
      planId: planId,
      title: 'Toplantı',
      dateTime: at ?? start,
      durationMinutes: duration,
    );
  }

  test('kapalıyken hiçbir takvim işlemi yapılmaz', () async {
    await sync('p1');
    await service.removePlan('p1');

    expect(only('upsertEvent'), isEmpty);
    expect(only('deleteEvent'), isEmpty);
  });

  test('tercih ve eşleşme hesaba göre ayrılır', () async {
    await service.enable();
    await sync('p1');

    expect(await service.isEnabled(), isTrue);

    currentUser = 'user-b';
    expect(await service.isEnabled(), isFalse);

    // B için kapalı: A'nın planına dokunamaz.
    await sync('p1');
    expect(only('upsertEvent'), hasLength(1));

    await service.enable();
    await sync('p2');

    final prefs = await SharedPreferences.getInstance();
    final a = jsonDecode(prefs.getString(AppleCalendarService.eventIdsKeyFor('user-a'))!) as Map;
    final b = jsonDecode(prefs.getString(AppleCalendarService.eventIdsKeyFor('user-b'))!) as Map;

    expect(a.keys, ['p1']);
    expect(b.keys, ['p2']);
  });

  test('eski global anahtarlar ilk kullanıcıya taşınır', () async {
    SharedPreferences.setMockInitialValues({
      'apple_calendar_sync_enabled': true,
      'apple_calendar_event_ids': jsonEncode({'p9': 'EV-9'}),
    });

    expect(await service.isEnabled(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('apple_calendar_sync_enabled'), isFalse);
    expect(prefs.containsKey('apple_calendar_event_ids'), isFalse);

    await sync('p9');
    expect((only('upsertEvent').single.arguments as Map)['eventId'], 'EV-9');
  });

  test('eşleşme varsa aynı etkinlik güncellenir, yoksa native tarafa eventId null gider',
      () async {
    await service.enable();

    await sync('p1');
    expect((only('upsertEvent')[0].arguments as Map)['eventId'], isNull);

    await sync('p1', at: start.add(const Duration(hours: 1)));
    expect((only('upsertEvent')[1].arguments as Map)['eventId'], 'EV-p1');
  });

  test('süre iletilir, belirtilmemişse 60 dk', () async {
    await service.enable();

    await sync('p1', duration: 120);
    await sync('p2');

    expect((only('upsertEvent')[0].arguments as Map)['durationMinutes'], 120);
    expect((only('upsertEvent')[1].arguments as Map)['durationMinutes'], 60);
  });

  test('silme: eşleşme kaybolsa da planId ile aranır; kapalıyken hiçbir şey silinmez',
      () async {
    await service.enable();
    await service.removePlan('lost');

    final del = only('deleteEvent').single.arguments as Map;
    expect(del['planId'], 'lost');
    expect(del['eventId'], isNull);

    calls.clear();
    await service.disable();
    await service.removePlan('p1');
    expect(only('deleteEvent'), isEmpty);
  });

  test('saat kaldırılan görevin Life Admin etkinliği kaldırılır', () async {
    await service.enable();
    await sync('p1');

    await service.syncPlan(
      planId: 'p1',
      title: 'Toplantı',
      dateTime: DateTime(2026, 10, 21), // saat yok
    );

    expect(only('deleteEvent'), hasLength(1));
  });

  test('yeniden kurma yalnızca kullanıcının kendi planlarını eşleştirir', () async {
    await service.enable();

    listedEvents = [
      {'planId': 'mine', 'eventId': 'EV-mine'},
      {'planId': 'someone-else', 'eventId': 'EV-x'},
    ];

    await service.reconcileMappings({'mine', 'other-own'});

    final prefs = await SharedPreferences.getInstance();
    final map = jsonDecode(prefs.getString(AppleCalendarService.eventIdsKeyFor('user-a'))!) as Map;

    expect(map, {'mine': 'EV-mine'});
    expect(only('deleteEvent'), isEmpty);

    // Kurulan eşleşme sonraki güncellemede kullanılır.
    await sync('mine');
    expect((only('upsertEvent').single.arguments as Map)['eventId'], 'EV-mine');
  });

  test('hesap silinince tercih ve eşleşme temizlenir, etkinlikler silinmez', () async {
    await service.enable();
    await sync('p1');
    calls.clear();

    await service.forgetUser('user-a');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AppleCalendarService.enabledKeyFor('user-a')), isFalse);
    expect(prefs.containsKey(AppleCalendarService.eventIdsKeyFor('user-a')), isFalse);
    expect(only('deleteEvent'), isEmpty);
  });
}
