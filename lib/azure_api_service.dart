import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AzureApiService {
  static Future<bool> sendTestToAzure(Map<String, dynamic> testData) async {
    try {
      // .env dosyasından IP adresimizi alıyoruz
      final String apiUrl = dotenv.env['AZURE_API_URL'] ?? '';

      if (apiUrl.isEmpty) {
        print("HATA: .env dosyasında AZURE_API_URL bulunamadı.");
        return false;
      }

      // SQLite verimizi Azure'un anlayacağı JSON formatına çeviriyoruz
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(testData),
      );

      // Sunucudan 200 (OK) veya 201 (Created) yanıtı geldiyse başarılıdır
      if (response.statusCode == 200 || response.statusCode == 201) {
        print("BAŞARILI: Veri Azure'a gönderildi!");
        return true;
      } else {
        print("HATA: Azure Sunucusu ${response.statusCode} hatası verdi.");
        return false;
      }
    } catch (e) {
      // İnternet yoksa veya sunucu kapalıysa uygulama ÇÖKMEZ, sadece bu hata basılır
      print(
          "BAĞLANTI HATASI: Veri buluta gönderilemedi. (Lokalde güvende) Detay: $e");
      return false;
    }
  }

  // Buluttaki tüm sürüş lokasyonlarını, RMS ve kullanıcı puanlarını çeken fonksiyon
  static Future<List<Map<String, dynamic>>> fetchGlobalLocations() async {
    try {
      final String apiUrl = dotenv.env['AZURE_API_URL'] ?? '';
      if (apiUrl.isEmpty) return [];

      // .env dosyasındaki URL'in sonuna /locations ekliyoruz
      // (Örn: http://IP_ADRESI:80/api/tests/locations)
      final String getUrl = apiUrl.endsWith('/api/tests')
          ? '$apiUrl/locations'
          : '$apiUrl/api/tests/locations';

      final response = await http.get(
        Uri.parse(getUrl),
        headers: {"Accept": "application/json; charset=utf-8"},
      );

      if (response.statusCode == 200) {
        // Türkçe karakter sorunu olmaması için utf8 ile decode ediyoruz
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'success') {
          print(
              "BAŞARILI: Harita verileri Azure'dan çekildi! Toplam: ${data['locations'].length} sürüş.");
          return List<Map<String, dynamic>>.from(data['locations']);
        }
      } else {
        print("HATA: Veriler çekilemedi. Sunucu Kodu: ${response.statusCode}");
      }
      return [];
    } catch (e) {
      print("BAĞLANTI HATASI: Harita verileri alınamadı. Detay: $e");
      return [];
    }
  }
}
