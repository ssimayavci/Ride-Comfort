import AppIntents
import UIKit

// 1. TESTİ BAŞLAT KOMUTU
@available(iOS 16.0, *)
struct StartTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Testi Başlat"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Flutter kanalına tetikleme gönderir
        NotificationCenter.default.post(name: Notification.Name("TriggerSiriIntent"), object: "com.emir.konforolcer.start_test")
        return .result()
    }
}

// 2. TESTİ BİTİR KOMUTU
@available(iOS 16.0, *)
struct StopTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Testi Bitir"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Flutter kanalına tetikleme gönderir
        NotificationCenter.default.post(name: Notification.Name("TriggerSiriIntent"), object: "com.emir.konforolcer.stop_test")
        return .result()
    }
}

// 3. SIFIR KURULUM (DÜZELTİLDİ)
@available(iOS 16.0, *)
struct RideComfortShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTestIntent(),
            phrases: [
                "\(.applicationName) testi başlat",
                "\(.applicationName) ile testi başlat"
            ]
        )
        AppShortcut(
            intent: StopTestIntent(),
            phrases: [
                "\(.applicationName) testi bitir",
                "\(.applicationName) ile testi bitir"
            ]
        )
    }
}
