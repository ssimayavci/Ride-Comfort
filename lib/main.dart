import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_siri_suggestions/flutter_siri_suggestions.dart';

import 'splash_screen.dart';

// ── GLOBAL STATE ─────────────────────────────────────────────────────────────
class SiriGlobalState {
  static final ValueNotifier<String?> siriIntentNotifier =
      ValueNotifier<String?>(null);
}

// ── CUSTOM CHANNEL ────────────────────────────────────────────────────────────
// Bypasses flutter_siri_suggestions' broken data stream.
const _siriChannel = MethodChannel('com.emir.konforolcer/siri');

// Calls getInitialIntent() on the native side and pushes the result into
// SiriGlobalState if a pending intent exists.
//
// Shared by two callers:
//   • main()                   — cold start (app was terminated)
//   • _SiriLifecycleObserver   — warm start (app resumes from background)
//
// On the native side, pendingActivityType is cleared after each read, so
// calling this multiple times is safe — subsequent calls return null.
Future<void> _pullPendingIntent() async {
  try {
    final String? intent =
        await _siriChannel.invokeMethod<String>('getInitialIntent');
    if (intent != null) {
      debugPrint("🌍 SIRI getInitialIntent: $intent");
      // Fazlalığı temizle
      final cleanIntent = intent.replaceAll('flutter_siri_suggestions-', '');
      SiriGlobalState.siriIntentNotifier.value = cleanIntent;
    }
  } catch (e) {
    debugPrint("🌍 SIRI getInitialIntent error: $e");
  }
}

// ── LIFECYCLE OBSERVER ────────────────────────────────────────────────────────
// Listens for AppLifecycleState.resumed and pulls any Siri intent that was
// stored in pendingActivityType on the native side during the paused-to-
// resuming transition window where invokeMethod pushes are silently dropped.
class _SiriLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🌍 LIFECYCLE: resumed — pulling pending Siri intent");
      _pullPendingIntent();
    }
  }
}

// ── MAIN ──────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Varsayılan .env dosyası bulunamadı, AI modülü çalışmayabilir.");
  }

  // Register the lifecycle observer before runApp so no resumed event is
  // missed during the initial engine startup sequence.
  WidgetsBinding.instance.addObserver(_SiriLifecycleObserver());

  // Push handler: receives onSiriIntent invocations from AppDelegate when
  // the Flutter engine is already fully running (app was in foreground or
  // the push happened to land after the engine resumed). Kept as a secondary
  // delivery path alongside the pull mechanism above.
  _siriChannel.setMethodCallHandler((call) async {
    if (call.method == 'onSiriIntent') {
      final String? activityType = call.arguments as String?;
      debugPrint("🌍 SIRI CHANNEL (push): $activityType");
      if (activityType != null) {
        // Fazlalığı temizle
        final cleanIntent =
            activityType.replaceAll('flutter_siri_suggestions-', '');
        SiriGlobalState.siriIntentNotifier.value = cleanIntent;
      }
    }
  });

  // Cold start pull: retrieves any intent that arrived via continue userActivity
  // before the method call handler above was registered.
  await _pullPendingIntent();

  // Plugin configure() must still be called so the plugin initialises its
  // internal state for the registerActivity() donation calls in
  // iso_comfort_screen.dart. onLaunch is a no-op fallback only.
  FlutterSiriSuggestions.instance.configure(
    onLaunch: (Map<String, dynamic> message) async {
      final String? activityType = message['activityType'] as String?;
      debugPrint("🌍 PLUGIN FALLBACK: $activityType");
      if (activityType != null &&
          SiriGlobalState.siriIntentNotifier.value == null) {
        SiriGlobalState.siriIntentNotifier.value = activityType;
      }
    },
  );

  runApp(const KonforOlcerApp());
}

// ── APP ───────────────────────────────────────────────────────────────────────
class KonforOlcerApp extends StatelessWidget {
  const KonforOlcerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ride Comfort',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
