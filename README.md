# 🚗 Konfor Ölçer (Ride Comfort Analysis)

Konfor Ölçer, araç içi sürüş konforunu **ISO 2631-1** standartlarına göre gerçek zamanlı olarak analiz eden, iOS cihazlar için geliştirilmiş native Siri destekli bir Flutter uygulamasıdır.

Uygulama; cihazın ivmeölçer verilerini kullanarak titreşimleri (RMS) ölçer, GPS üzerinden anomali tespiti yapar ve sürüş bittiğinde **Google Gemini AI** kullanarak detaylı bir uzman konfor raporu sunar.

## ✨ Öne Çıkan Özellikler

* **Gerçek Zamanlı FFT Analizi:** 50Hz örnekleme hızı ve 512-point FFT penceresi ile ISO 2631-1 frekans ağırlıklandırması (Wk/Wd).
* **Akıllı Anomali Tespiti:** Arka planda çalışan algoritma ile güzergah üzerindeki sert titreşimleri (çukur/kasis) harita üzerinde coğrafi olarak etiketler.
* **Apple Siri Entegrasyonu:** Sürüş esnasında dikkati dağıtmamak için "Testi başlat" ve "Testi bitir" komutlarıyla eller serbest kullanım.
* **Gemini AI Destekli Raporlama:** Yol durumu, cihaz konumu ve araç parametrelerini harmanlayarak kullanıcıya özel yapay zeka analiz raporları üretir.
* **CSV Dışa Aktarma:** Akademik incelemeler ve mühendislik analizleri için MATLAB uyumlu ham veri dışa aktarımı.

## 🛠️ Kullanılan Teknolojiler & Kütüphaneler

* **Core & UI:** Flutter, Dart, `fl_chart` (Gerçek zamanlı grafikler)
* **Donanım & Sensör:** `sensors_plus` (İvmeölçer), `geolocator` (GPS), `wakelock_plus` (Ekran uyanıklığı)
* **Harita & Konum:** `flutter_map`, `latlong2`
* **Veri İşleme:** `fftea` (Hızlı Fourier Dönüşümü), `sqflite` (Yerel veri tabanı)
* **Yapay Zeka:** `google_generative_ai` (Gemini 2.5 Flash Lite API)
* **Native iOS Entegrasyonları:** `flutter_siri_suggestions`

## 🚀 Kurulum & Çalıştırma

Projeyi kendi bilgisayarınızda derlemek ve çalıştırmak için aşağıdaki adımları izleyin.

### 1. Ön Koşullar
* Flutter SDK (Sürüm 3.x)
* macOS bilgisayar ve Xcode (iOS derlemesi için zorunludur)
* CocoaPods (`sudo gem install cocoapods`)

### 2. Projeyi Klonlama ve Paketleri İndirme
Terminali açın ve projeyi bilgisayarınıza klonlayın:
```bash
git clone https://github.com/ssimayavci/Ride-Comfort.git
cd Ride-Comfort
flutter clean
flutter pub get
```

### 3. Ortam Değişkenleri (.env) Kurulumu
Yapay zeka raporlama özelliğinin çalışması için bir Google Gemini API anahtarına ihtiyacınız vardır. Projenin ana dizininde `.env` adında yeni bir dosya oluşturun ve içine anahtarınızı ekleyin. *(Not: .env dosyası güvenlik sebebiyle GitHub'a yüklenmez, bu işlemi projeyi indiren her geliştirici kendi anahtarıyla yerel olarak yapmalıdır).*
```env
GEMINI_API_KEY=sizin_api_anahtariniz_buraya
```

### 4. iOS Bağımlılıklarının Kurulumu
Siri ve diğer native iOS paketlerinin düzgün çalışması için Pod'ları yükleyin:
```bash
cd ios
pod install
cd ..
```

### 5. Uygulamayı Çalıştırma
Kurulum tamamlandıktan sonra fiziksel bir iPhone bağlayarak veya iOS Simulator üzerinden uygulamayı başlatabilirsiniz:
```bash
flutter run
```

## 📂 Veritabanı Mimarisi

Sistem verilerini yerel `tests_history.db` SQLite veritabanında saklar:
* **`tests` Tablosu:** Sürüş oturumunun temel metrikleri (RMS skoru, ortalama hız, başlangıç/bitiş koordinatları).
* **`road_anomalies` Tablosu:** İlgili sürüşte tespit edilen anlık şokların koordinatları ve tepe şiddetleri.
* **`global_hazards` Tablosu:** Tüm testlerden toplanan ve birbirine 30 metre mesafede olan tehlikeleri kümeleyen global uyarı önbelleği.

## 👥 Ekip & Geliştiriciler

Bu uygulama bir bilgisayar mühendisliği bitirme projesi kapsamında geliştirilmiştir.

* **Simay Avcı - Emir Chousein:** Mobil Uygulama Geliştirme (Flutter), Sensör Veri İşleme (FFT), Yapay Zeka (Gemini API), Native iOS/Siri Entegrasyonları, Proje Mimarisi ve Native iOS Çekirdek Yapılandırması