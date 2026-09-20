import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// Apple/iOS tarzı, light/dark tema ile senkron silme onayı. Klasik Material
// AlertDialog yerine tüm uygulamada tutarlı, premium bir görünüm sağlar.
//
// CupertinoTheme'i burada elle Theme.of(context).brightness ile kuruyoruz;
// aksi halde CupertinoAlertDialog, uygulamanın kendi tema seçimini değil
// cihazın ham MediaQuery parlaklığını kullanır ve kullanıcı uygulama içinden
// "Koyu" seçtiğinde bile dialog açık gelebilir.
Future<bool> showPremiumConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Vazgeç',
  String confirmLabel = 'Sil',
  bool isDestructive = true,
}) async {
  final theme = Theme.of(context);

  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return CupertinoTheme(
        data: CupertinoThemeData(
          brightness: theme.brightness,
          primaryColor: theme.colorScheme.primary,
        ),
        child: CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            CupertinoDialogAction(
              isDestructiveAction: isDestructive,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );

  return result ?? false;
}
