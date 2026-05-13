import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TYPED EXCEPTIONS
//
// Using typed exceptions instead of sentinel strings means callers can catch
// specific failure modes with `on AiQuotaException` rather than inspecting
// arbitrary substrings of a return value — which breaks silently if the text
// ever changes.
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the Gemini API quota is exhausted (HTTP 429).
class AiQuotaException implements Exception {
  final String message;
  const AiQuotaException(this.message);
  @override
  String toString() => message;
}

/// Thrown for any other Gemini API or configuration error.
class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);
  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────

class AiService {
  /// Generates a Turkish automotive analysis report for the given test session.
  ///
  /// Returns the Markdown report string on success.
  /// Throws [AiQuotaException] on HTTP 429 / quota exhaustion.
  /// Throws [AiServiceException] on any other error.
  static Future<String> generateRideAnalysis(
    Map<String, dynamic> testData,
    List<Map<String, dynamic>> anomalies,
  ) async {
    final String? apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw AiServiceException(
          'GEMINI_API_KEY bulunamadı. Lütfen .env konfigürasyonunu kontrol edin.');
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      systemInstruction: Content.system(
          'Sen bir Otomotiv Süspansiyon, Şasi ve Yol Kalitesi uzmanısın. '
          'Sana verilen telemetri verilerini ve anomali (çukur/kasis) kayıtlarını '
          'inceleyerek, yolun durumu ve aracın konforu hakkında maksimum 3-4 '
          'cümlelik, profesyonel, teknik ve Türkçe bir analiz raporu yaz. '
          'Markdown kullanabilirsin.'),
    );

    final double score = (testData['score'] as num?)?.toDouble() ?? 0.0;
    final String vehicle =
        testData['vehicle_info'] as String? ?? 'Belirtilmedi';
    final String tire = testData['tire_info'] as String? ?? 'Belirtilmedi';
    final String placement =
        testData['phone_placement'] as String? ?? 'Belirtilmedi';
    final double distance =
        (testData['distance_km'] as num?)?.toDouble() ?? 0.0;
    final int duration = (testData['duration_seconds'] as int?) ?? 0;
    final int anomalyCount = (testData['anomaly_count'] as int?) ?? 0;

    // FIX #9: Include speed statistics — highly relevant for suspension analysis.
    // e.g. high vibration at 80 km/h vs low-speed cobblestone context are
    // very different findings for a road-quality assessment.
    final double avgSpeed =
        (testData['average_speed'] as num?)?.toDouble() ?? 0.0;
    final double speedDev =
        (testData['speed_deviation'] as num?)?.toDouble() ?? 0.0;

    String prompt = '''
Oturum Telemetri Verileri:
- Araç: $vehicle
- Lastik: $tire
- Sensör Konumu: $placement
- Toplam Sürüş Süresi: $duration saniye
- Toplam Sürüş Mesafesi: ${distance.toStringAsFixed(2)} km
- Ortalama Seyir Hızı: ${avgSpeed.toStringAsFixed(1)} km/s
- Hız Sapması (Sürüş Tutarsızlığı): ±${speedDev.toStringAsFixed(1)} km/s
- Toplam RMS Titreşim Skoru (ISO 2631): ${score.toStringAsFixed(3)} m/s²
- Tespit Edilen Ağır Şok / Kasis (Anomali) Sayısı: $anomalyCount
''';

    if (anomalies.isNotEmpty) {
      prompt += '\nAnomali Detayları (Pik Titreşim Skorları):\n';
      for (var i = 0; i < anomalies.length; i++) {
        final double peak =
            (anomalies[i]['peak_score'] as num?)?.toDouble() ?? 0.0;
        prompt += '- İhlal Noktası ${i + 1}: ${peak.toStringAsFixed(3)} m/s²\n';
      }
    }

    prompt +=
        '\nLütfen bu verileri referans alarak profesyonel bir zemin ve süspansiyon durum raporu yaz.';

    // Retry loop — handles transient 503 overloads with up to 3 attempts.
    const int maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await model.generateContent([Content.text(prompt)]);
        final String? text = response.text;
        if (text == null || text.isEmpty) {
          throw AiServiceException(
              'API boş yanıt döndü. Lütfen tekrar deneyin.');
        }
        return text;
      } catch (e) {
        // Already a typed exception — propagate immediately without retrying.
        if (e is AiQuotaException || e is AiServiceException) rethrow;

        final String err = e.toString().toLowerCase();
        final bool isQuota = err.contains('429') ||
            err.contains('quota exceeded') ||
            err.contains('exhausted');
        final bool isOverload = err.contains('503') ||
            err.contains('unavailable') ||
            err.contains('overloaded') ||
            err.contains('generativeaiexception');

        if (isQuota) {
          throw AiQuotaException(
              'KOTA AŞILDI: Google sunucularına çok fazla istek gönderildi. '
              'Lütfen yaklaşık 30 saniye bekleyip tekrar deneyin.');
        }

        if (isOverload && attempt < maxRetries - 1) {
          // Transient server overload — wait and retry.
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        debugPrint('AI Service Error: $e');
        throw AiServiceException('YZ modülüne erişilirken bir hata oluştu: $e');
      }
    }

    // Unreachable in practice, but required to satisfy the type system.
    throw AiServiceException(
        'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.');
  }
}
