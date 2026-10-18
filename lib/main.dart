import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'features/profile/purchase_service.dart';
import 'services/notification_service.dart';
import 'services/session_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Uygulama genelinde varsayılan dikey (portrait) kilit — SADECE Pomodoro
  // ekranı bu kilidi kendi initState/dispose'unda geçici olarak açıp
  // (route bazlı) yatay moda izin veriyor; oradan çıkınca kilit buraya
  // geri döner. Diğer tüm ekranlar her zaman portraitUp'ta kalır.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Türkçe tarih / takvim verileri
  await initializeDateFormatting('tr_TR', null);

  // Supabase
  await Supabase.initialize(
    url: 'https://kqtyprnvvvrnsqywzhhl.supabase.co',
    publishableKey: 'sb_publishable_JngB7wKAoL1vknAlGfAVdg_Aqcaqi3l',
  );

  // Bildirim sistemi
  await NotificationService.instance.initialize();

  // Oturum/bildirim uzlaştırması: çıkışta yerel bildirimleri temizler; giriş,
  // yeniden açılış ve öne gelişte Supabase'deki hatırlatmaları yeniden kurar.
  SessionSyncService.instance.start();

  // Satın alma (in_app_purchase) transaction listener'ı — Apple'ın kendi
  // önerdiği gibi mümkün olduğunca erken bağlanıyor: uygulama kapalıyken
  // tamamlanan bir işlem, purchaseStream üzerinden bir sonraki açılışta
  // gelebilir. App Store'a ulaşmayı BEKLEMEDEN (await'siz) başlatılıyor ki
  // giriş ekranı bu ağ çağrısının arkasında kilitlenmesin.
  unawaited(PurchaseService.instance.initialize());

  runApp(const LifeAdminApp());
}
