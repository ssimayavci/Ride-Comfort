import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var pendingActivityType: String?
  private var siriChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 🚨 CLAUDE'UN SİLDİĞİ ANA ŞALTER! Bu olmadan hiçbir eklenti (TTS, Sqflite vs.) çalışmaz.
    GeneratedPluginRegistrant.register(with: self)
    
    // 2. KESİN ÇÖZÜM (Ekranı beklemeden direkt motora bağlanan kanal)
    if let registrar = self.registrar(forPlugin: "SiriIntentBridge") {
        let messenger = registrar.messenger()
        
        siriChannel = FlutterMethodChannel(
            name: "com.emir.konforolcer/siri",
            binaryMessenger: messenger
        )
        
        siriChannel?.setMethodCallHandler { [weak self] call, flutterResult in
            if call.method == "getInitialIntent" {
                flutterResult(self?.pendingActivityType)
                self?.pendingActivityType = nil
            } else {
                flutterResult(FlutterMethodNotImplemented)
            }
        }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {

    let activityType = userActivity.activityType
    print("🔥 NATIVE iOS YAKALADI: \(activityType ?? "Bilinmiyor")")

    pendingActivityType = activityType
    siriChannel?.invokeMethod("onSiriIntent", arguments: activityType)

    var enrichedInfo: [AnyHashable: Any] = userActivity.userInfo ?? [:]
    enrichedInfo["activityType"] = activityType
    userActivity.userInfo = enrichedInfo

    restorationHandler(nil)
    return true
  }
}