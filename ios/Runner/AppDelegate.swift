import AudioToolbox
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    UNUserNotificationCenter.current().delegate =
        self as? UNUserNotificationCenterDelegate

    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(
      with: engineBridge.pluginRegistry
    )

    // Görev tamamlama sesi: Flutter'ın kendi SystemSound API'si (click/
    // alert/tick) "tamamlandı" hissi vermediği için, iOS'un kendi kısa/
    // yumuşak sistem seslerinden birini harici bir ses dosyası eklemeden
    // çalmak için küçük bir MethodChannel köprüsü. Dart tarafı:
    // calendar_page.dart -> _playTaskCompletedSound().
    let soundChannel = FlutterMethodChannel(
      name: "life_admin/sound",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    soundChannel.setMethodCallHandler { call, result in
      if call.method == "playTaskCompleted" {
        // 1520 ("Pop"): Apple'ın kısa, yumuşak, düşük perdeli sistem
        // sesi — "click"e (1306) göre çok daha "tok" ve rahatsız etmeyen
        // bir tamamlama hissi verir. Beğenilmezse tek satırlık bu ID
        // kolayca değiştirilebilir.
        AudioServicesPlaySystemSound(1520)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}