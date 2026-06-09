import Flutter
import UIKit
import Intents
import IntentsUI

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Caches the intent that arrives before Dart's getInitialIntent() is ready.
  private var pendingActivityType: String?

  // Custom MethodChannel that bypasses flutter_siri_suggestions' broken stream.
  private var siriChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ── COLD LAUNCH SAFETY NET ────────────────────────────────────────────
    // When launched from the Shortcuts app or by a Siri voice command, iOS
    // embeds the NSUserActivity type in launchOptions. Extracting it here
    // guarantees pendingActivityType is set BEFORE the Flutter engine calls
    // getInitialIntent, closing the race window that caused the two-tap bug.
    if let activityDict = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any],
       let activityType = activityDict[UIApplication.LaunchOptionsKey.userActivityType] as? String {
      pendingActivityType = activityType
      print("🔥 COLD LAUNCH from shortcut (launchOptions): \(activityType)")
    }

    // 🚨 Must remain before channel setup — registers TTS, SQLite, etc.
    GeneratedPluginRegistrant.register(with: self)

    // ── SIRI BRIDGE CHANNEL ───────────────────────────────────────────────
    // Uses FlutterAppDelegate's FlutterPluginRegistry conformance so the
    // messenger is obtained without requiring a UIWindow reference — safe
    // for both scene-based and legacy app lifecycles.
    if let registrar = self.registrar(forPlugin: "SiriIntentBridge") {
      let messenger = registrar.messenger()

      siriChannel = FlutterMethodChannel(
        name: "com.emir.konforolcer/siri",
        binaryMessenger: messenger
      )

      siriChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {

        case "getInitialIntent":
          // Pull mechanism: Dart calls this on cold start and on every resume.
          result(self?.pendingActivityType)
          self?.pendingActivityType = nil

        case "addToSiri":
          // Presents INUIAddVoiceShortcutViewController so the user can record
          // a personal Siri phrase. If the shortcut was already added, shows
          // the edit sheet instead.
          guard let activityType = call.arguments as? String else {
            result(FlutterError(
              code: "INVALID_ARGS",
              message: "addToSiri expects a String activityType",
              details: nil))
            return
          }
          self?.presentAddToSiri(activityType: activityType, result: result)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── ADD TO SIRI ───────────────────────────────────────────────────────────
  private func presentAddToSiri(activityType: String, result: @escaping FlutterResult) {
    let activity = NSUserActivity(activityType: activityType)
    if activityType.hasSuffix("start_test") {
      activity.title = "Testi Başlat"
      activity.suggestedInvocationPhrase = "Testi başlat"
    } else {
      activity.title = "Testi Bitir"
      activity.suggestedInvocationPhrase = "Testi bitir"
    }
    activity.isEligibleForPrediction = true
    activity.isEligibleForSearch = true

    let shortcut = INShortcut(userActivity: activity)

    INVoiceShortcutCenter.shared.getAllVoiceShortcuts { [weak self] shortcuts, _ in
      DispatchQueue.main.async {
        let existing = shortcuts?.first {
          $0.shortcut.userActivity?.activityType == activityType
        }

        let vc: UIViewController
        if let existing = existing {
          let editVC = INUIEditVoiceShortcutViewController(voiceShortcut: existing)
          editVC.delegate = self
          vc = editVC
        } else {
          let addVC = INUIAddVoiceShortcutViewController(shortcut: shortcut)
          addVC.delegate = self
          vc = addVC
        }

        // Walk up to the topmost presented view controller to avoid conflicts.
        guard var topVC = self?.window?.rootViewController else {
          result(FlutterError(code: "NO_VC", message: "No root view controller", details: nil))
          return
        }
        while let presented = topVC.presentedViewController {
          topVC = presented
        }
        topVC.present(vc, animated: true)
        result(nil)
      }
    }
  }

  // ── SIRI SHORTCUT INTENT ──────────────────────────────────────────────────
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    let activityType = userActivity.activityType
    print("🔥 NATIVE iOS YAKALADI: \(activityType)")

    // Buffer for the pull path (getInitialIntent, called on resume or cold start).
    pendingActivityType = activityType

    // Push path: delivers immediately if the Flutter engine is fully running.
    // Silently dropped during the paused→resuming window — pull path covers that.
    siriChannel?.invokeMethod("onSiriIntent", arguments: activityType)

    restorationHandler(nil)

    // Return true here — do NOT call super to avoid scene-machinery 4608 errors.
    return true
  }
}

// MARK: - INUIAddVoiceShortcutViewControllerDelegate
extension AppDelegate: INUIAddVoiceShortcutViewControllerDelegate {
  func addVoiceShortcutViewController(
    _ controller: INUIAddVoiceShortcutViewController,
    didFinishWith voiceShortcut: INVoiceShortcut?,
    error: Error?
  ) {
    controller.dismiss(animated: true)
  }

  func addVoiceShortcutViewControllerDidCancel(
    _ controller: INUIAddVoiceShortcutViewController
  ) {
    controller.dismiss(animated: true)
  }
}

// MARK: - INUIEditVoiceShortcutViewControllerDelegate
extension AppDelegate: INUIEditVoiceShortcutViewControllerDelegate {
  func editVoiceShortcutViewController(
    _ controller: INUIEditVoiceShortcutViewController,
    didUpdate voiceShortcut: INVoiceShortcut?,
    error: Error?
  ) {
    controller.dismiss(animated: true)
  }

  func editVoiceShortcutViewController(
    _ controller: INUIEditVoiceShortcutViewController,
    didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID
  ) {
    controller.dismiss(animated: true)
  }

  func editVoiceShortcutViewControllerDidCancel(
    _ controller: INUIEditVoiceShortcutViewController
  ) {
    controller.dismiss(animated: true)
  }
}
