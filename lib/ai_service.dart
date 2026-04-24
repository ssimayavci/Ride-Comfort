import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:io';

class AiService {
  static Future<void> _checkAvailableModels(String apiKey) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey'));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody);
      if (data['models'] != null) {
        for (var model in data['models']) {
          print("Available Model: ${model['name']}");
        }
      } else {
        print("Model List API Error: $responseBody");
      }
    } catch (e) {
      print("Could not fetch models: $e");
    }
  }

  static Future<String> generateRideAnalysis(Map<String, dynamic> testData,
      List<Map<String, dynamic>> anomalies) async {
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    print("API Key check: ${apiKey?.substring(0, 5)}...");
    if (apiKey == null || apiKey.isEmpty) {
      return "⚠️ **HATA**: `GEMINI_API_KEY` sistemde bulunamadı. Lütfen `.env` konfigürasyonunu kontrol edin.";
      throw Exception(
          "⚠️ **HATA**: `GEMINI_API_KEY` sistemde bulunamadı. Lütfen `.env` konfigürasyonunu kontrol edin.");
    }

    await _checkAvailableModels(apiKey);

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash-lite',
        apiKey: apiKey,
        systemInstruction: Content.system(
            "Sen bir Otomotiv Süspansiyon, Şasi ve Yol Kalitesi uzmanısın. Sana verilen telemetri verilerini ve anomali (çukur/kasis) kayıtlarını inceleyerek, yolun durumu ve aracın konforu hakkında maksimum 3-4 cümlelik, profesyonel, teknik ve Türkçe bir analiz raporu yaz. Markdown kullanabilirsin."),
      );

      final double score = testData['score'] ?? 0.0;
      final String vehicle = testData['vehicle_info'] ?? 'Belirtilmedi';
      final String tire = testData['tire_info'] ?? 'Belirtilmedi';
      final String placement = testData['phone_placement'] ?? 'Belirtilmedi';
      final double distance = testData['distance_km'] ?? 0.0;
      final int duration = testData['duration_seconds'] ?? 0;
      final int anomalyCount = testData['anomaly_count'] ?? 0;

      String prompt = """
Oturum Telemetri Verileri:
- Araç: $vehicle
- Lastik: $tire
- Sensör Konumu: $placement
- Toplam Sürüş Süresi: $duration saniye
- Toplam Sürüş Mesafesi: ${distance.toStringAsFixed(2)} km
- Toplam RMS Titreşim Skoru (ISO 2631): ${score.toStringAsFixed(3)} m/s²
- Tespit Edilen Ağır Şok / Kasis (Anomali) Sayısı: $anomalyCount
""";

      if (anomalies.isNotEmpty) {
        prompt += "\nAnomali Detayları (Pik Titreşim Skorları):\n";
        for (var i = 0; i < anomalies.length; i++) {
          final peak = (anomalies[i]['peak_score'] as num?)?.toDouble() ?? 0.0;
          prompt +=
              "- İhlal Noktası ${i + 1}: ${peak.toStringAsFixed(3)} m/s²\n";
        }
      }

      prompt +=
          "\nLütfen bu verileri referans alarak profesyonel bir zemin ve süspansiyon durum raporu yaz.";

      int maxRetries = 3;
      for (int i = 0; i < maxRetries; i++) {
        try {
          final response = await model.generateContent([Content.text(prompt)]);
          return response.text ?? "Rapor oluşturulamadı, API boş yanıt döndü.";
        } catch (e) {
          final errorString = e.toString().toLowerCase();

          if (errorString.contains('429') ||
              errorString.contains('quota exceeded') ||
              errorString.contains('exhausted')) {
            throw Exception(
                'KOTA AŞILDI: Lütfen yaklaşık 30 saniye bekleyip tekrar deneyin.');
          }

          if (errorString.contains('503') ||
              errorString.contains('generativeaiexception') ||
              errorString.contains('unavailable') ||
              errorString.contains('overloaded')) {
            if (i == maxRetries - 1) {
              return "⚠️ **KOTA AŞILDI**: Sunucu kapasitesi dolu. Lütfen daha sonra tekrar deneyiniz.";
            }
            await Future.delayed(const Duration(seconds: 3));
          } else {
            rethrow;
          }
        }
      }

      return "⚠️ **HATA**: İşlem zaman aşımına uğradı.";
    } catch (e) {
      final String externalErr = e.toString().toLowerCase();
      if (externalErr.contains('429') || externalErr.contains('quota')) {
        return "⚠️ **KOTA AŞILDI**: Çok fazla istek gönderildi. Lütfen yaklaşık 30 saniye bekleyip tekrar deneyiniz.";
      }
      debugPrint("AI Service Error: $e");
      return "⚠️ **HATA**: YZ modülüne erişilirken bir istisna fırlatıldı.\n\n$e";
    }
  }
}
