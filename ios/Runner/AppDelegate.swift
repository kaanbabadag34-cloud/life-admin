import ActivityKit
import AudioToolbox
import AVFoundation
import EventKit
import Flutter
import Speech
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
    // Apple Takvim (EventKit) köprüsü — Dart tarafı:
    // lib/services/apple_calendar_service.dart.
    let calendarBridge = CalendarBridge()
    let calendarChannel = FlutterMethodChannel(
      name: "life_admin/calendar",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    calendarChannel.setMethodCallHandler { call, result in
      calendarBridge.handle(call, result: result)
    }

    // Sesli görev: iOS Speech framework (tr-TR) köprüsü — Dart tarafı:
    // lib/services/speech_service.dart.
    let speechChannel = FlutterMethodChannel(
      name: "life_admin/speech",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    let speechBridge = SpeechBridge(channel: speechChannel)
    speechChannel.setMethodCallHandler { call, result in
      speechBridge.handle(call, result: result)
    }

    // Pomodoro Live Activity (ActivityKit) köprüsü — Dart tarafı:
    // lib/services/pomodoro_live_activity.dart.
    let liveActivityBridge = LiveActivityBridge()
    let liveActivityChannel = FlutterMethodChannel(
      name: "life_admin/live_activity",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    liveActivityChannel.setMethodCallHandler { call, result in
      liveActivityBridge.handle(call, result: result)
    }

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

// EventKit köprüsü. NOT: Etkinlikleri sonradan GÜNCELLEYEBİLMEK/SİLEBİLMEK
// için tam takvim erişimi gerekiyor — iOS 17+ "yalnızca yazma" erişimi
// oluşturulan etkinlikleri okuyup değiştirmeye/silmeye izin vermiyor.
// Life Admin'ın oluşturduğu her etkinlik `lifeadmin://plan/<id>` URL'i ile
// işaretlenir; güncelleme/silme yalnızca bu işaretli etkinliklere uygulanır.
final class CalendarBridge {
  private let store = EKEventStore()
  private let urlScheme = "lifeadmin"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "authorizationStatus":
      result(authorizationStatusString())
    case "requestAccess":
      requestAccess(result)
    case "upsertEvent":
      upsertEvent(call.arguments, result)
    case "deleteEvent":
      deleteEvent(call.arguments, result)
    case "listOurEvents":
      listOurEvents(call.arguments, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func planUrlString(_ planId: String) -> String {
    return "\(urlScheme)://plan/\(planId)"
  }

  // Yalnızca Life Admin'ın işaretli etkinlikleri; [planId] verilirse yalnızca
  // o göreve ait olanlar. Kullanıcının kendi etkinlikleri ASLA dönmez.
  private func findOurEvents(planId: String?, from: Date, to: Date) -> [EKEvent] {
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
    let wanted = planId.map { planUrlString($0) }

    return store.events(matching: predicate).filter { event in
      guard isOurs(event), let url = event.url?.absoluteString else { return false }
      if let wanted = wanted { return url == wanted }
      return true
    }
  }

  private func hasAccess() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func authorizationStatusString() -> String {
    if hasAccess() { return "granted" }
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: return "notDetermined"
    default: return "denied"
    }
  }

  private func requestAccess(_ result: @escaping FlutterResult) {
    let completion: (Bool, Error?) -> Void = { granted, _ in
      DispatchQueue.main.async { result(granted) }
    }

    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: completion)
    } else {
      store.requestAccess(to: .event, completion: completion)
    }
  }

  private func isOurs(_ event: EKEvent) -> Bool {
    return event.url?.scheme == urlScheme
  }

  private func upsertEvent(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard hasAccess() else {
      result(FlutterError(code: "no_access", message: "Takvim erişimi yok.", details: nil))
      return
    }

    guard
      let args = arguments as? [String: Any],
      let planId = args["planId"] as? String,
      let title = args["title"] as? String,
      let startMillis = args["startMillis"] as? Int
    else {
      result(FlutterError(code: "bad_args", message: "Geçersiz argümanlar.", details: nil))
      return
    }

    let durationMinutes = args["durationMinutes"] as? Int ?? 60
    let notes = args["notes"] as? String

    var event: EKEvent?
    if let eventId = args["eventId"] as? String,
       let existing = store.event(withIdentifier: eventId),
       isOurs(existing) {
      event = existing
    }

    // Yerel eşleşme kaybolduysa (uygulama yeniden yüklendi vb.) bu göreve ait,
    // Life Admin işaretli etkinlik takvimde aranır ve YENİDEN KULLANILIR; böylece
    // aynı görev takvime ikinci kez eklenmez.
    if event == nil {
      let start = Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000.0)
      let day: TimeInterval = 86400
      event = findOurEvents(
        planId: planId,
        from: start.addingTimeInterval(-366 * day),
        to: start.addingTimeInterval(366 * day)
      ).first
    }

    let target: EKEvent
    if let existing = event {
      target = existing
    } else {
      guard let calendar = store.defaultCalendarForNewEvents else {
        result(FlutterError(code: "no_calendar", message: "Varsayılan takvim yok.", details: nil))
        return
      }
      target = EKEvent(eventStore: store)
      target.calendar = calendar
    }

    let start = Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000.0)
    target.title = title
    target.startDate = start
    target.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
    target.notes = notes
    target.url = URL(string: "\(urlScheme)://plan/\(planId)")

    do {
      try store.save(target, span: .thisEvent, commit: true)
      result(target.eventIdentifier)
    } catch {
      result(FlutterError(code: "save_failed", message: "Etkinlik kaydedilemedi.", details: nil))
    }
  }

  // Silme: önce eşleşen etkinlik kimliğiyle; kimlik yoksa/geçersizse göreve ait
  // Life Admin işaretli etkinlikler planId ile aranır. Her durumda YALNIZCA
  // Life Admin işaretli etkinlikler silinir.
  private func deleteEvent(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard hasAccess() else {
      result(FlutterError(code: "no_access", message: "Takvim erişimi yok.", details: nil))
      return
    }

    guard let args = arguments as? [String: Any] else {
      result(FlutterError(code: "bad_args", message: "Geçersiz argümanlar.", details: nil))
      return
    }

    let eventId = args["eventId"] as? String
    let planId = args["planId"] as? String

    var targets: [EKEvent] = []

    if let eventId = eventId,
       let event = store.event(withIdentifier: eventId),
       isOurs(event) {
      targets = [event]
    } else if let planId = planId {
      let now = Date()
      let year: TimeInterval = 365 * 86400
      targets = findOurEvents(
        planId: planId,
        from: now.addingTimeInterval(-2 * year),
        to: now.addingTimeInterval(2 * year)
      )
    }

    guard !targets.isEmpty else {
      result(false)
      return
    }

    do {
      for event in targets {
        try store.remove(event, span: .thisEvent, commit: true)
      }
      result(true)
    } catch {
      result(FlutterError(code: "delete_failed", message: "Etkinlik silinemedi.", details: nil))
    }
  }

  // Life Admin işaretli etkinlikleri (planId -> eventId) listeler; yerel
  // eşleşmeyi yeniden kurmak için kullanılır. Kullanıcının kendi etkinliklerine
  // dokunmaz/döndürmez.
  private func listOurEvents(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard hasAccess() else {
      result(FlutterError(code: "no_access", message: "Takvim erişimi yok.", details: nil))
      return
    }

    guard
      let args = arguments as? [String: Any],
      let startMillis = args["startMillis"] as? Int,
      let endMillis = args["endMillis"] as? Int
    else {
      result(FlutterError(code: "bad_args", message: "Geçersiz argümanlar.", details: nil))
      return
    }

    let from = Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000.0)
    let to = Date(timeIntervalSince1970: TimeInterval(endMillis) / 1000.0)
    let prefix = "\(urlScheme)://plan/"

    let entries: [[String: String]] = findOurEvents(planId: nil, from: from, to: to)
      .compactMap { event in
        guard
          let url = event.url?.absoluteString,
          url.hasPrefix(prefix),
          let eventId = event.eventIdentifier
        else { return nil }
        return ["planId": String(url.dropFirst(prefix.count)), "eventId": eventId]
      }

    result(entries)
  }
}

// Pomodoro Live Activity köprüsü. Uygulama iOS 15'i destekliyor; ActivityKit
// iOS 16.2+ gerektirdiği için her şey #available ile korunur ve desteklenmeyen
// / Live Activities kapalı durumlarda Pomodoro normal çalışmaya devam eder.
final class LiveActivityBridge {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(false)
      return
    }

    switch call.method {
    case "isSupported":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "sync":
      sync(call.arguments, result)
    case "end":
      end(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.2, *)
  private func sync(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(false)
      return
    }

    guard
      let args = arguments as? [String: Any],
      let isBreak = args["isBreak"] as? Bool,
      let isRunning = args["isRunning"] as? Bool,
      let endMillis = args["endMillis"] as? Int,
      let remaining = args["remainingSeconds"] as? Int,
      let total = args["totalSeconds"] as? Int,
      total > 0
    else {
      result(false)
      return
    }

    let endDate = Date(timeIntervalSince1970: TimeInterval(endMillis) / 1000.0)
    let state = PomodoroAttributes.ContentState(
      isBreak: isBreak,
      isRunning: isRunning,
      endDate: endDate,
      startDate: endDate.addingTimeInterval(-TimeInterval(total)),
      remainingSeconds: remaining,
      totalSeconds: total
    )
    let content = ActivityContent(state: state, staleDate: nil)

    Task {
      let existing = Activity<PomodoroAttributes>.activities

      if let first = existing.first {
        // Artık kalmış yinelenen etkinlikleri kapat, ilkini güncelle.
        for extra in existing.dropFirst() {
          await extra.end(nil, dismissalPolicy: .immediate)
        }
        await first.update(content)
        result(true)
        return
      }

      do {
        _ = try Activity.request(
          attributes: PomodoroAttributes(name: "Pomodoro"),
          content: content,
          pushType: nil
        )
        result(true)
      } catch {
        result(false)
      }
    }
  }

  @available(iOS 16.2, *)
  private func end(_ result: @escaping FlutterResult) {
    Task {
      for activity in Activity<PomodoroAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      result(true)
    }
  }
}

// Basılı tutarak sesli görev için konuşma tanıma köprüsü. Ses SADECE bellekte
// tanıma motoruna beslenir: dosyaya yazılmaz, sunucumuza gönderilmez. Cihaz
// destekliyorsa tanıma cihaz üzerinde (on-device) yapılır.
final class SpeechBridge {
  private let channel: FlutterMethodChannel
  private let audioEngine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var lastText = ""
  private var lastConfidence: Double = 0
  private var isActive = false
  private var isFinishing = false
  private var isCancelled = false
  private var hasDelivered = false
  private var lastLevelSent = Date.distantPast
  private var finalFallback: DispatchWorkItem?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  // Tanıma motoruna bağlam ipucu: Türkçe tarih, saat ve hatırlatma ifadeleri.
  static let contextualPhrases: [String] = [
    "yarın", "bugün", "öbür gün", "haftaya", "pazartesi", "salı", "çarşamba",
    "perşembe", "cuma", "cumartesi", "pazar", "sabah", "öğleden sonra", "akşam",
    "gece", "saat", "buçuk", "çeyrek", "yarım saat", "dakika önce", "saat önce",
    "gün önce", "dakika sonra", "saat sonra", "hatırlat", "beni uyar",
    "bildirim gönder", "tam saatinde", "randevu", "toplantı", "dişçi",
    "deneme sınavı", "on yedi otuz", "yirmi dakika önce", "saat beşte",
    "saat üçte", "saat sekizde",
  ]

  // Segment güvenlerinin ortalaması (0 = bilinmiyor).
  static func averageConfidence(_ transcription: SFTranscription) -> Double {
    let values = transcription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStatus":
      result(permissionStatus())
    case "requestPermissions":
      requestPermissions(result)
    case "start":
      start(result)
    case "stop":
      stop()
      result(true)
    case "cancel":
      cancel()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func permissionStatus() -> String {
    let speech = SFSpeechRecognizer.authorizationStatus()
    let mic = AVAudioSession.sharedInstance().recordPermission

    if speech == .authorized && mic == .granted { return "granted" }
    if speech == .restricted { return "restricted" }
    if speech == .denied || mic == .denied { return "denied" }
    return "notDetermined"
  }

  private func requestPermissions(_ result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { [weak self] _ in
      AVAudioSession.sharedInstance().requestRecordPermission { _ in
        DispatchQueue.main.async {
          result(self?.permissionStatus() ?? "denied")
        }
      }
    }
  }

  private func send(_ method: String, _ argument: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod(method, arguments: argument)
    }
  }

  private func start(_ result: @escaping FlutterResult) {
    guard !isActive else {
      result(false)
      return
    }

    guard permissionStatus() == "granted" else {
      result(false)
      return
    }

    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    guard let recognizer = recognizer, recognizer.isAvailable else {
      result(false)
      return
    }

    self.recognizer = recognizer
    lastText = ""
    lastConfidence = 0
    isFinishing = false
    isCancelled = false
    hasDelivered = false

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      // Doğruluk için Apple'ın standart (sunucu destekli) tanıması kullanılır;
      // cihaz üstü Türkçe model daha zayıf ("yarın"/"yarım" karışıyor).
      request.requiresOnDeviceRecognition = false
      request.taskHint = .dictation
      // Türkçe tarih/saat/hatırlatma ifadelerine öncelik ver.
      request.contextualStrings = SpeechBridge.contextualPhrases
      self.request = request

      task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
        guard let self = self else { return }

        DispatchQueue.main.async {
          if self.isCancelled { return }

          if let recognition = recognition {
            self.lastText = recognition.bestTranscription.formattedString
            self.lastConfidence = SpeechBridge.averageConfidence(recognition.bestTranscription)

            if recognition.isFinal {
              self.deliverFinal()
            } else {
              self.send("partial", self.lastText)
            }
          }

          if error != nil && !self.hasDelivered {
            if self.isFinishing {
              self.deliverFinal()
            } else {
              self.fail("recognition_failed")
            }
          }
        }
      }

      let inputNode = audioEngine.inputNode
      let format = inputNode.outputFormat(forBus: 0)
      inputNode.removeTap(onBus: 0)
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
        guard let self = self else { return }
        self.request?.append(buffer)
        self.reportLevel(buffer)
      }

      audioEngine.prepare()
      try audioEngine.start()
      isActive = true
      result(true)
    } catch {
      teardown()
      result(false)
    }
  }

  private func reportLevel(_ buffer: AVAudioPCMBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastLevelSent) > 0.05 else { return }
    lastLevelSent = now

    guard let data = buffer.floatChannelData?[0] else { return }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return }

    var sum: Float = 0
    for i in 0..<count { sum += data[i] * data[i] }
    let rms = sqrt(sum / Float(count))
    let db = 20 * log10(max(rms, 1e-7))
    let normalized = max(0, min(1, (db + 50) / 50))

    send("level", Double(normalized))
  }

  // Parmak kaldırıldı: ses girişi biter ama SON sonuç beklenir (metin erken
  // kesilmez). Sonuç gelmezse kısa bir zaman aşımıyla eldeki metin kullanılır.
  private func stop() {
    guard isActive, !isFinishing else { return }
    isFinishing = true

    // Parmak kalkarken söylenen son kelimeler kesilmesin: kayda kısa bir süre
    // daha devam edip sonra ses girişini bitiriyoruz.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self = self, !self.isCancelled, !self.hasDelivered else { return }
      self.stopAudio()
      self.request?.endAudio()

      let fallback = DispatchWorkItem { [weak self] in
        self?.deliverFinal()
      }
      self.finalFallback = fallback
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fallback)
    }
  }

  private func cancel() {
    isCancelled = true
    teardown()
  }

  private func deliverFinal() {
    guard !hasDelivered, !isCancelled else { return }
    hasDelivered = true
    let text = lastText
    let confidence = lastConfidence
    // Sonuç ÖNCE iletilir, ses oturumunun kapatılması beklenmez.
    send("final", ["text": text, "confidence": confidence])
    teardown()
  }

  private func fail(_ code: String) {
    guard !hasDelivered, !isCancelled else { return }
    hasDelivered = true
    teardown()
    send("error", code)
  }

  private func stopAudio() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)
  }

  // Mikrofonu ve ses oturumunu serbest bırakır.
  private func teardown() {
    finalFallback?.cancel()
    finalFallback = nil

    stopAudio()
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    recognizer = nil
    isActive = false

    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
