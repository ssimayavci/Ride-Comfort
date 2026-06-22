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
}
