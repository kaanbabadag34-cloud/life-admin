import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Türkçe tarih / takvim verileri
  await initializeDateFormatting(
    'tr_TR',
    null,
  );

  // Supabase
  await Supabase.initialize(
    url: 'https://kqtyprnvvvrnsqywzhhl.supabase.co',
    publishableKey:
        'sb_publishable_JngB7wKAoL1vknAlGfAVdg_Aqcaqi3l',
  );

  // Bildirim sistemi
  await NotificationService.instance.initialize();

  runApp(
    const LifeAdminApp(),
  );
}