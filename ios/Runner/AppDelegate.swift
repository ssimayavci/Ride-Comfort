import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  
  // Siri'den gelen komutu Flutter uyanana kadar hafızada tutmak için
  var pendingSiriIntent: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let siriChannel = FlutterMethodChannel(name: "com.emir.konforolcer/siri", binaryMessenger: controller.binaryMessenger)
      
    // 1. PULL: Flutter'ın "Bekleyen komut var mı?" sorusuna cevap veren kısım
    siriChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getInitialIntent" {
            result(self.pendingSiriIntent)
            self.pendingSiriIntent = nil // Okuduktan sonra hafızayı temizle
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
      
    // 2. PUSH: Siri App Intents tetiklendiğinde çalışan kısım
    NotificationCenter.default.addObserver(forName: Notification.Name("TriggerSiriIntent"), object: nil, queue: .main) { notification in
        if let intentStr = notification.object as? String {
            self.pendingSiriIntent = intentStr // Flutter kapalıysa diye hafızaya al
            siriChannel.invokeMethod("onSiriIntent", arguments: intentStr) // Flutter açıksa anında ilet
        }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
