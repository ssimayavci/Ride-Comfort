import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fftea/fftea.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'database_helper.dart';
import 'history_screen.dart';

class IsoComfortScreen extends StatefulWidget {
  const IsoComfortScreen({super.key});

  @override
  State<IsoComfortScreen> createState() => _IsoComfortScreenState();
}

class _IsoComfortScreenState extends State<IsoComfortScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  //makinecilerin depolama listesi
  final List<String> _machineDataRows = [];
  final List<String> _validationRows = [];
  bool _isRunning = false;

//FFT'nin calısması icin gereken veri boyutu
  static const int _fftWindowSize = 512;
  static const double _samplingRate = 50.0;
//depolama bufferları
  final List<double> _bufferX = [];
  final List<double> _bufferY = [];
  final List<double> _bufferZ = [];
  final List<double> _timeBuffer = [];

  int _tickCount = 0;
  double _timeCounterChart = 0;
  final List<FlSpot> _chartData = [];
  static const int _maxDataPoints = 60;
// rms skorlarını tutan liste
  final List<double> _sessionRmsScores = [];

  double? _gravityX;
  double? _gravityY;
  double? _gravityZ;
  //Telefonun yerçekimini saf sarsıntıdan ayırmak için kullanılır.
  static const double _alpha = 0.1;

  double? _finalRmsAv;
  Position? _currentPosition;

  StreamSubscription<Position>? _positionSubscription;
  //GPS koordinatlarını tutan liste
  final List<LatLng> _routeMap = [];
  double _totalDistanceKm = 0.0;
  DateTime? _testStartTime;
  int _durationSeconds = 0;

  DateTime? _lastAnomalyTime;
  //anomali verilerini tutan liste
  final List<Map<String, dynamic>> _sessionAnomalies = [];

  // Hız ve Sapma Değişkenleri
  double _currentSpeedKmh = 0.0;
  double _averageSpeedKmh = 0.0;
  double _speedDeviation = 0.0; // Standart Sapma (+/-)
  final List<double> _speedHistory =
      []; // Sapmayı hesaplamak için tüm hızları burada biriktireceğiz

  final TextEditingController _vehicleInfoController = TextEditingController();
  final TextEditingController _tireInfoController = TextEditingController();
  String _selectedPhonePlacement = "Yolcu Koltuğu";

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _vehicleInfoController.dispose();
    _tireInfoController.dispose();
    _pulseController.dispose();
    _accelerometerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _showPreTestDialog() {
    String tempPlacement = _selectedPhonePlacement;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: _GlassCard(
              borderGlow: Colors.greenAccent.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'TEST PARAMETRELERİ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 24),
                      const Text('Araç Bilgisi',
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blueGrey.withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: _vehicleInfoController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: "Örn: Renault Megane 4",
                            hintStyle: TextStyle(color: Colors.blueGrey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Lastik Bilgisi',
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blueGrey.withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: _tireInfoController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: "Örn: 205/55 R16 Yaz Lastiği",
                            hintStyle: TextStyle(color: Colors.blueGrey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Telefon Konumu',
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blueGrey.withOpacity(0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempPlacement,
                            dropdownColor: const Color(0xFF0F172A),
                            icon: const Icon(Icons.arrow_drop_down,
                                color: Colors.greenAccent),
                            isExpanded: true,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                            onChanged: (String? newValue) {
                              setDialogState(() {
                                tempPlacement = newValue!;
                              });
                            },
                            items: <String>[
                              "Yolcu Koltuğu",
                              "Konsol / Torpido",
                              "Ön Cam Tutucu",
                              "Zemin"
                            ].map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('İPTAL'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.greenAccent.withOpacity(0.2),
                                foregroundColor: Colors.greenAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                        color: Colors.greenAccent
                                            .withOpacity(0.5))),
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedPhonePlacement = tempPlacement;
                                });
                                Navigator.pop(context);
                                _startTest();
                              },
                              child: const Text('ONAYLA',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _startTest() {
    HapticFeedback.lightImpact();
    setState(() {
      _isRunning = true;
      _finalRmsAv = null;
      _chartData.clear();
      // Sinyal işleme (FFT) sepetlerini tamamen boşalt.
      _bufferX.clear();
      _bufferY.clear();
      _bufferZ.clear();
      _timeBuffer.clear();
      _sessionRmsScores.clear();
      _timeCounterChart = 0;
      _tickCount = 0;
// Yerçekimi filtresini ve konumu sıfırla.
      _gravityX = null;
      _gravityY = null;
      _gravityZ = null;
      _currentPosition = null;

      _routeMap.clear();
      _totalDistanceKm = 0.0;
      _testStartTime = DateTime.now(); //Kronometreyi tam şu an başlat.
      _durationSeconds = 0;

      _lastAnomalyTime = null;
      _sessionAnomalies.clear();

      _currentSpeedKmh = 0.0;
      _averageSpeedKmh = 0.0;
      _speedDeviation = 0.0;
      _speedHistory.clear();

      _machineDataRows.clear();
      _machineDataRows
          .add("Zaman_s;Ivme_X;Ivme_Y;Ivme_Z;Frekans_Hz;FFT_X;FFT_Y;FFT_Z");
    });
//Arka planda konum takip motorunu çalıştırır.
    _fetchLocationAndStartStream();

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      if (!_isRunning) return;
// Telefonun durduğu yerdeki 9.81 m/s² olan sabit yerçekimini buluruz (_alpha = 0.1).
      _gravityX = _gravityX == null
          ? event.x
          : _alpha * event.x + (1 - _alpha) * _gravityX!;
      _gravityY = _gravityY == null
          ? event.y
          : _alpha * event.y + (1 - _alpha) * _gravityY!;
      _gravityZ = _gravityZ == null
          ? event.z
          : _alpha * event.z + (1 - _alpha) * _gravityZ!;
      // Gelen anlık veriden, tespit ettiğimiz bu yerçekimini çıkartırız.
      // dx, dy, dz: Artık elimizde sadece aracın hareketiyle oluşan SAF SARSINTI var.
      final double dx = event.x - _gravityX!;
      final double dy = event.y - _gravityY!;
      final double dz = event.z - _gravityZ!;
      //Testin başından beri kaç saniye geçti?
      double elapsedSeconds = (DateTime.now().millisecondsSinceEpoch -
              _testStartTime!.millisecondsSinceEpoch) /
          1000.0;
      String time = elapsedSeconds.toStringAsFixed(3);

      _machineDataRows.add(
          "$time;${dx.toStringAsFixed(4)};${dy.toStringAsFixed(4)};${dz.toStringAsFixed(4)};;;;;");
//// Gelen verileri FFT'de kullanmak üzere hafıza listelerine atıyoruz.
      _timeBuffer.add(elapsedSeconds);
      _bufferX.add(dx);
      _bufferY.add(dy);
      _bufferZ.add(dz);
      _tickCount++; //// Sepete giren yeni veri sayısını tutar.

      // Sepetimizin maksimum kapasitesi _fftWindowSize (512).
      // Kapasite dolarsa, sepetin dibindeki en eski 1. veriyi (index 0) çöpe atıyoruz.
      // Böylece elimizde her zaman en güncel 512 verilik bir paket kalıyor.
      if (_bufferX.length > _fftWindowSize) {
        _bufferX.removeAt(0);
        _bufferY.removeAt(0);
        _bufferZ.removeAt(0);
        _timeBuffer.removeAt(0);
      }
      // Eğer sepet tam kapasiteye (512) ulaştıysa VE içeriye tam 1 saniyelik (50 adet) YENİ veri girdiyse...
      if (_bufferX.length == _fftWindowSize && _tickCount >= 50) {
        _tickCount = 0; // Sayacı sıfırla.
        _calculateBlockRms(); // Konfor skorunu hesapla, grafiği çizdir
      }
    });
  }

  void _calculateBlockRms() {
    double totalTime = _timeBuffer.last - _timeBuffer.first;
    // N-1 verinin geliş süresine bakarak o anki 'Gerçek Frekansı (Hz)' hesaplıyoruz.
    double realFs = (_fftWindowSize - 1) / totalTime;
    //FFT sonucunda her bir adımın kaç Hz'e denk geldiğini buluyoruz
    final double df = realFs / _fftWindowSize;

    // --- 1. DC COMPONENT TEMİZLİĞİ (ZERO-MEAN / DETRENDING) ---
    double meanX = _bufferX.reduce((a, b) => a + b) / _fftWindowSize;
    double meanY = _bufferY.reduce((a, b) => a + b) / _fftWindowSize;
    double meanZ = _bufferZ.reduce((a, b) => a + b) / _fftWindowSize;

    // KRİTİK DÜZELTME: Orijinal buffer'ı BOZMADAN, hesaplama için geçici kopya listeler oluşturuyoruz.
    // Böylece CSV'ye basılacak ham veri korunmuş oluyor ve Sliding Window mantığı bozulmuyor.
    List<double> detrendedX = _bufferX.map((e) => e - meanX).toList();
    List<double> detrendedY = _bufferY.map((e) => e - meanY).toList();
    List<double> detrendedZ = _bufferZ.map((e) => e - meanZ).toList();
    // ----------------------------------------------------------

    // --- 2. WINDOWING (SİNYAL PÜRÜZSÜZLEŞTİRME) ---
    // 1.852 Katsayısının Anlamı (Amplitude Correction Factor):
    // Hanning/Hamming penceresi sinyalin kenarlarını sıfıra bastırırken toplam enerjiyi azaltır (Coherent Gain ~ 0.54).
    // Sinyalin genliğini gerçek fiziksel seviyesine geri çekmek için (1 / 0.54 = 1.8518...) katsayısı ile çarpılır.
    List<double> windowedX = List.generate(_fftWindowSize, (i) {
      double w = (0.54 - 0.46 * cos(2 * pi * i / (_fftWindowSize - 1))) * 1.852;
      return detrendedX[i] *
          w; // Orijinal _bufferX yerine detrendedX kullanıldı
    });

    List<double> windowedY = List.generate(_fftWindowSize, (i) {
      double w = (0.54 - 0.46 * cos(2 * pi * i / (_fftWindowSize - 1))) * 1.852;
      return detrendedY[i] *
          w; // Orijinal _bufferY yerine detrendedY kullanıldı
    });

    List<double> windowedZ = List.generate(_fftWindowSize, (i) {
      double w = (0.54 - 0.46 * cos(2 * pi * i / (_fftWindowSize - 1))) * 1.852;
      return detrendedZ[i] *
          w; // Orijinal _bufferZ yerine detrendedZ kullanıldı
    });

    final fft = FFT(_fftWindowSize);
    //saf frekansa ayrıştırma işlemi(çorba örneği)
    final resX = fft.realFft(windowedX);
    final resY = fft.realFft(windowedY);
    final resZ = fft.realFft(windowedZ);
//sarsıntıların şiddetini biriktirip olusturulan sepet
    double sumSqX = 0;
    double sumSqY = 0;
    double sumSqZ = 0;
// FFT'ninçıkardığı sonuçların ikinci yarısı, ilk yarısının aynısıdır (Buna Nyquist Teoremi denir)
    for (int i = 1; i < _fftWindowSize ~/ 2; i++) {
      //Bandın üzerinden o an geçen titreşimin frekansını (Hz) hesaplıyoruz
      double f = i * df;
      //sarsıntının gerçek "Büyüklüğünü (magX)" buluyoruz.(Dik kenarların karelerinin toplamının karekökü)
      double magX = sqrt(resX[i].x * resX[i].x + resX[i].y * resX[i].y);
      double magY = sqrt(resY[i].x * resY[i].x + resY[i].y * resY[i].y);
      double magZ = sqrt(resZ[i].x * resZ[i].x + resZ[i].y * resZ[i].y);

      // Gerçek fiziksel genliğe (m/s²) dönüştürme işlemi (Normalizasyon)
      double ampX = magX / (_fftWindowSize / 2);
      double ampY = magY / (_fftWindowSize / 2);
      double ampZ = magZ / (_fftWindowSize / 2);
      //makinecilerin verilerini csv ye yazdırma islemi
      if (i == 1) {
        double elapsedSeconds = (DateTime.now().millisecondsSinceEpoch -
                _testStartTime!.millisecondsSinceEpoch) /
            1000.0;
        String time = elapsedSeconds.toStringAsFixed(3);
        _machineDataRows.add(
            "$time;;;;${f.toStringAsFixed(2)};${ampX.toStringAsFixed(4)};${ampY.toStringAsFixed(4)};${ampZ.toStringAsFixed(4)}");
      } else {
        _machineDataRows.add(
            ";;;;${f.toStringAsFixed(2)};${ampX.toStringAsFixed(4)};${ampY.toStringAsFixed(4)};${ampZ.toStringAsFixed(4)}");
      }
      //insan hassasiyeti filtresi(karınca ornegi)-ıso 2631
      // --- MAKİNE EKİBİ HASSAS KATSAYILARI İLE DOĞRU RMS HESAPLAMA ---
      // 1. Hassas ISO katsayılarını çekiyoruz
      double wd = _getWdWeighting(f);
      double wk = _getWkWeighting(f);

      // 2. Agirliklandirilmis_X = FFT_X * Wd
      double weightedX = ampX * wd;
      double weightedY = ampY * wd;
      double weightedZ = ampZ * wk;

      // 3. FİZİKTEKİ DOĞRU GÜÇ HESABI (PARSEVAL TEOREMİ)
      // Senin eski kodunda olduğu gibi, toplamı nBins'e BÖLMÜYORUZ.
      // Sadece (Genlik^2) / 2 formülüyle gerçek enerjiyi sepete atıyoruz.
      sumSqX += (weightedX * weightedX) / 2.0;
      sumSqY += (weightedY * weightedY) / 2.0;
      sumSqZ += (weightedZ * weightedZ) / 2.0;
    } // <-- FOR DÖNGÜSÜNÜN BİTİŞİ BURASI

    // 4. Gerçek enerjiyi bulmak için doğrudan karekök alıyoruz (Bölme yok!)
    double rmsX = sqrt(sumSqX);
    double rmsY = sqrt(sumSqY);
    double rmsZ = sqrt(sumSqZ);

    // 5. Üç eksenin toplam bileşkesi (Bileşke RMS)
    double finalBlockAv = sqrt(rmsX * rmsX + rmsY * rmsY + rmsZ * rmsZ);

    if (finalBlockAv > 1.25) {
      // Bu skor 1.25'ten büyük mü? Demek ki çok rahatsız edici bir çukura veya kasise girdik!" diyor.
      if (finalBlockAv > 2.5) {
        HapticFeedback.heavyImpact(); //guclu titresim veriyor.
      } else {
        HapticFeedback.mediumImpact(); //orta derecede titresim veriyor.
      }

      // 2. Anomaliyi Kaydetme (Database İçin)
      final now = DateTime.now();
      if (_lastAnomalyTime == null ||
          //"Bir çukur tespit edip kaydettiysen, 2.5 saniye boyunca gözlerini kapat.
          // Aynı çukurun yankılarını tekrar tekrar kaydetme.".
          now.difference(_lastAnomalyTime!).inMilliseconds > 2500) {
        _lastAnomalyTime = now;
        //Test bitince haritada gördüğün o yuvarlak kırmızı uyarı işaretleri, tam olarak bu listedeki koordinatlara bakılarak çiziliyor
        if (_currentPosition != null) {
          _sessionAnomalies.add({
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
            'timestamp': now.toIso8601String(),
            'peak_score': finalBlockAv
          });
        }
      }
    }
    // --- GEÇİCİ DOĞRULAMA CSV'Sİ DOLDURMA ALANI ---
    if (_validationRows.isEmpty) {
      // 1. Senin ve Makine ekibinin istediği yeni başlıklar:
      _validationRows
          .add("Zaman_s;Ivme_X;Ivme_Y;Ivme_Z;Frekans_Hz;FFT_X;FFT_Y;FFT_Z");

      double realFs = 50.0; // Saniyedeki veri sayımız (50 Hz)
      double df =
          realFs / _fftWindowSize; // Her bir FFT adımının Frekans karşılığı

      for (int i = 0; i < _fftWindowSize; i++) {
        // İndeks yerine tam Zamanı (Saniye) hesaplıyoruz
        double timeSec = i * (1.0 / realFs);
        String t = timeSec.toStringAsFixed(3);

        String rawX = _bufferX[i].toStringAsFixed(4);
        String rawY = _bufferY[i].toStringAsFixed(4);
        String rawZ = _bufferZ[i].toStringAsFixed(4);

        if (i < _fftWindowSize ~/ 2) {
          // Frekansı hesaplıyoruz (Hz)
          double f = i * df;

          double mX = sqrt(resX[i].x * resX[i].x + resX[i].y * resX[i].y);
          double mY = sqrt(resY[i].x * resY[i].x + resY[i].y * resY[i].y);
          double mZ = sqrt(resZ[i].x * resZ[i].x + resZ[i].y * resZ[i].y);

          double aX = mX / (_fftWindowSize / 2);
          double aY = mY / (_fftWindowSize / 2);
          double aZ = mZ / (_fftWindowSize / 2);

          // Frekans sütunu eklendi
          _validationRows.add(
              "$t;$rawX;$rawY;$rawZ;${f.toStringAsFixed(2)};${aX.toStringAsFixed(4)};${aY.toStringAsFixed(4)};${aZ.toStringAsFixed(4)}");
        } else {
          // FFT'nin olmadığı alt satırlarda frekans ve FFT sütunları boş bırakılıyor
          _validationRows.add("$t;$rawX;$rawY;$rawZ;;;;");
        }
      }
    }
    // ----------------------------------------------

    setState(() {
      _sessionRmsScores.add(finalBlockAv);
      _finalRmsAv = finalBlockAv;

      _chartData.add(FlSpot(_timeCounterChart, finalBlockAv));
      _timeCounterChart += 1;

      if (_chartData.length > _maxDataPoints) {
        _chartData.removeAt(0);
      }
    });
  }

  //uygulama konum ayarlaeını acıp acmadıgını kontrol ediyor sonrasında ise toplam kaç km gidildigini hesaplıyor
  Future<void> _fetchLocationAndStartStream() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (_currentPosition != null && _isRunning) {
        setState(() {
          _routeMap.add(
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
        });
      }
    } catch (e) {
      debugPrint("Init loc failed: $e");
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((Position position) {
      if (!_isRunning) return;
      if (position.accuracy > 25.0) return;

      final newPoint = LatLng(position.latitude, position.longitude);

      // m/s cinsinden gelen hızı 3.6 ile çarparak km/h'ye çeviriyoruz.
      // GPS bazen hata verip negatif hız döndürebilir, onu sıfıra eşitliyoruz.
      double currentSpeed = position.speed * 3.6;
      if (currentSpeed < 0) currentSpeed = 0.0;

      setState(() {
        _currentSpeedKmh = currentSpeed;

        // Araç durmuyorsa (kırmızı ışıkta vb. beklemiyorsa) hızı listeye kaydet.
        // Sıfırları listeye doldurmak ortalama hızı ve sapmayı bozar.
        if (currentSpeed > 2.0) {
          _speedHistory.add(currentSpeed);
          _calculateSpeedStats(); // YENİ: Canlı güncellenmesi için buraya ekledik!
        }
      });

      if (_routeMap.isNotEmpty && _currentPosition != null) {
        final distance =
            const Distance().as(LengthUnit.Meter, _routeMap.last, newPoint);
        final timeDiff = position.timestamp
                .difference(_currentPosition!.timestamp)
                .inMilliseconds /
            1000.0;

        if (timeDiff > 0) {
          final speedMs = distance / timeDiff;
          if (speedMs > 45.0) return;
        }

        if (distance < 3.0) {
          _currentPosition = position;
          return;
        }
        setState(() {
          _totalDistanceKm += distance / 1000.0;
          _currentPosition = position;
          _routeMap.add(newPoint);
          if (_testStartTime != null) {
            _durationSeconds =
                DateTime.now().difference(_testStartTime!).inSeconds;
          }
        });
      } else {
        setState(() {
          _currentPosition = position;
          _routeMap.add(newPoint);
        });
      }
    });
  }

  //FFT'den gelen her bir frekansı alır, hangi aralığa düştüğüne bakar ve
  // o frekansın RMS hesabında kullanılacak 0 ile 1 arasındaki çarpım katsayısını belirler.
  // --- MAKİNE EKİBİ ISO 2631 HASSAS KATSAYILARI VE İNTERPOLASYON MOTORU ---
  static const List<double> _isoFreqs = [
    0.1,
    0.125,
    0.16,
    0.2,
    0.25,
    0.315,
    0.4,
    0.5,
    0.63,
    0.8,
    1.0,
    1.25,
    1.6,
    2.0,
    2.5,
    3.15,
    4.0,
    5.0,
    6.3,
    8.0,
    10.0,
    12.5,
    16.0,
    20.0,
    25.0,
    31.5,
    40.0,
    50.0,
    63.0,
    80.0,
    100.0,
    125.0,
    160.0,
    200.0,
    250.0,
    315.0,
    400.0
  ];

  // Python kodundaki / 1000 işlemi Dart'ta listeye işlenmiştir
  static const List<double> _wkRaw = [
    0.0312,
    0.0486,
    0.079,
    0.121,
    0.182,
    0.263,
    0.352,
    0.418,
    0.459,
    0.477,
    0.482,
    0.484,
    0.494,
    0.531,
    0.631,
    0.804,
    0.967,
    1.039,
    1.054,
    1.036,
    0.988,
    0.902,
    0.768,
    0.636,
    0.513,
    0.405,
    0.314,
    0.246,
    0.186,
    0.132,
    0.0887,
    0.054,
    0.0285,
    0.0152,
    0.0079,
    0.00398,
    0.00195
  ];

  static const List<double> _wdRaw = [
    0.0624,
    0.0973,
    0.158,
    0.243,
    0.365,
    0.530,
    0.713,
    0.853,
    0.944,
    0.992,
    1.011,
    1.008,
    0.968,
    0.890,
    0.776,
    0.642,
    0.512,
    0.409,
    0.323,
    0.253,
    0.212,
    0.161,
    0.125,
    0.100,
    0.080,
    0.0632,
    0.0494,
    0.0388,
    0.0295,
    0.0211,
    0.0141,
    0.00863,
    0.00455,
    0.00243,
    0.00126,
    0.00064,
    0.00031
  ];

  // Python'daki numpy.interp fonksiyonunun birebir Dart karşılığı
  double _interp(double x, List<double> xp, List<double> fp) {
    if (x <= xp.first) return fp.first;
    if (x >= xp.last) return fp.last;
    for (int i = 0; i < xp.length - 1; i++) {
      if (x >= xp[i] && x <= xp[i + 1]) {
        double t = (x - xp[i]) / (xp[i + 1] - xp[i]);
        return fp[i] + t * (fp[i + 1] - fp[i]);
      }
    }
    return 0.0;
  }

  // X ve Y ekseni için
  double _getWdWeighting(double f) {
    return _interp(f, _isoFreqs, _wdRaw);
  }

  // Z ekseni için (Makine ekibinin kullandığı standart)
  double _getWkWeighting(double f) {
    return _interp(f, _isoFreqs, _wkRaw);
  }
  // --------------------------------------------------------------------------

  void _stopTest() {
    if (!_isRunning) return;
    HapticFeedback.lightImpact();

    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_testStartTime != null) {
      _durationSeconds = DateTime.now().difference(_testStartTime!).inSeconds;
    }

    setState(() {
      _isRunning = false;
    });

    _calculateSpeedStats();
    _calculateIsoComfort();
    _autoExportMachineData();
  }

  void _calculateSpeedStats() {
    if (_speedHistory.isEmpty) return;

    // 1. Ortalama Hızı Hesapla (Tüm hızları topla ve eleman sayısına böl)
    double sum = 0;
    for (double speed in _speedHistory) {
      sum += speed;
    }
    _averageSpeedKmh = sum / _speedHistory.length;

    // 2. Standart Sapmayı (Dalgalanmayı) Hesapla
    double varianceSum = 0;
    for (double speed in _speedHistory) {
      // (Anlık Hız - Ortalama Hız) değerinin karesini alıp topluyoruz
      varianceSum += pow(speed - _averageSpeedKmh, 2);
    }

    // Varyansın karekökünü alarak sapma miktarını buluyoruz
    _speedDeviation = sqrt(varianceSum / _speedHistory.length);
  }

  Future<void> _autoExportMachineData() async {
    if (_validationRows.isEmpty)
      return; // Eski listeyi değil, yenisini kontrol ediyoruz
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Doğrulama verisi hazırlanıyor...')),
        );
      }
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/FFT_Dogrulama_Verisi.csv');
      await file.writeAsString(_validationRows.join('\n'));
      await Share.shareXFiles([XFile(file.path)],
          text: 'MATLAB Doğrulama Verisi (512 Ham vs 256 FFT)');
    } catch (e) {
      debugPrint("Auto-Export Error: $e");
    }
  }

  //_calculateIsoComfort() fonksiyonu,
  //test bittiğinde yolculuğun genel konfor skorunu hesaplayarak tüm sürüş verilerini
  //veritabanına kalıcı olarak kaydeder.
  // İlk olarak, test boyunca saniyede bir toplanan sarsıntı skorlarının
  // (_sessionRmsScores) karelerinin ortalamasının karekökünü alarak (RMS yöntemiyle)
  // yolculuğun nihai konfor değerini (_finalRmsAv) hesaplar.
  // Ardından; başlangıç ve bitiş koordinatları, toplam mesafe, süre, kullanıcıdan alınan araç/lastik bilgileri, telefon konumu ve JSON formatına çevrilmiş harita rotası gibi
  // tüm parametreleri tek bir veri paketi (testData) haline getirir.
  // Son olarak, bu paketi veritabanına (DatabaseHelper.instance.insertTest)
  // yeni bir sürüş oturumu olarak kaydeder ve
  // yolculuk sırasında tespit edilen tüm anomalileri de bu oturum kimliğiyle (session_id)
  // veritabanına ekleyerek işlemi tamamlar.

  Future<void> _calculateIsoComfort() async {
    if (_sessionRmsScores.isEmpty) {
      setState(() {
        _finalRmsAv = 0.0;
      });
      return;
    }

    double sumSq = 0.0;
    for (double av in _sessionRmsScores) {
      sumSq += (av * av);
    }
    double totalTripAv = sqrt(sumSq / _sessionRmsScores.length);

    setState(() {
      _finalRmsAv = totalTripAv;
    });

    final now = DateTime.now();

    double? startLat;
    double? startLng;
    double? endLat;
    double? endLng;

    if (_routeMap.isNotEmpty) {
      startLat = _routeMap.first.latitude;
      startLng = _routeMap.first.longitude;
      endLat = _routeMap.last.latitude;
      endLng = _routeMap.last.longitude;
    }

    final testData = {
      'timestamp': now.toIso8601String(),
      'score': _finalRmsAv,
      'latitude': _currentPosition?.latitude,
      'longitude': _currentPosition?.longitude,
      'note': '',
      'distance_km': _totalDistanceKm,
      'duration_seconds': _durationSeconds,
      'average_speed': _averageSpeedKmh, // YENİ
      'speed_deviation': _speedDeviation, // YENİ
      'start_lat': startLat,
      'start_lng': startLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'anomaly_count': _sessionAnomalies.length,
      'vehicle_info': _vehicleInfoController.text.trim().isEmpty
          ? null
          : _vehicleInfoController.text.trim(),
      'tire_info': _tireInfoController.text.trim().isEmpty
          ? null
          : _tireInfoController.text.trim(),
      'phone_placement': _selectedPhonePlacement,
      'route_points': jsonEncode(_routeMap
          .map((ll) => {'lat': ll.latitude, 'lng': ll.longitude})
          .toList())
    };

    int newSessionId = await DatabaseHelper.instance.insertTest(testData);

    for (var anomaly in _sessionAnomalies) {
      anomaly['session_id'] = newSessionId;
      await DatabaseHelper.instance.insertAnomaly(anomaly);
    }
  }

  (String, Color) _getComfortLabel(double rms) {
    if (rms < 0.315) return ("Çok rahat", Colors.greenAccent);
    if (rms < 0.63) return ("Biraz rahatsız", Colors.lightGreenAccent);
    if (rms < 1.0) return ("Oldukça rahatsız", Colors.orangeAccent);
    if (rms < 1.6) return ("Rahatsız", Colors.deepOrangeAccent);
    if (rms < 2.5) return ("Çok rahatsız", Colors.redAccent);
    return ("Aşırı rahatsız", Colors.red);
  }

  Widget _buildMap() {
    if (_routeMap.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.02)),
        child: const Center(
          child: Text('GPS Sinyali Bekleniyor...',
              style: TextStyle(color: Colors.blueGrey)),
        ),
      );
    }

    return SizedBox(
      height: 250,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: _routeMap.last,
          initialZoom: 16.0,
        ),
        children: [
          ColorFiltered(
            colorFilter:
                const ColorFilter.mode(Colors.black54, BlendMode.darken),
            child: TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.konfor_olcer',
            ),
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routeMap,
                strokeWidth: 4.0,
                color: const Color(0xFF39FF14),
              )
            ],
          ),
          MarkerLayer(
            markers: [
              if (_routeMap.isNotEmpty)
                Marker(
                  point: _routeMap.first,
                  width: 20,
                  height: 20,
                  child: const Icon(Icons.circle,
                      color: Colors.blueAccent, size: 14),
                ),
              if (_routeMap.length > 1)
                Marker(
                  point: _routeMap.last,
                  width: 20,
                  height: 20,
                  child: const Icon(Icons.my_location,
                      color: Color(0xFF39FF14), size: 16),
                ),
              ..._sessionAnomalies.map((a) {
                return Marker(
                    point: LatLng(a['lat'], a['lng']),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, boxShadow: [
                        BoxShadow(
                            color: const Color(0xFFFF3131).withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 4)
                      ]),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFFF3131), size: 28),
                    ));
              }),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minX = _chartData.isEmpty
        ? 0.0
        : (_chartData.length < _maxDataPoints ? 0.0 : _chartData.first.x);
    final maxX = _chartData.isEmpty
        ? _maxDataPoints.toDouble()
        : (_chartData.length < _maxDataPoints
            ? _maxDataPoints.toDouble()
            : _chartData.last.x);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("ISO 2631 Konfor Analizi",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF020617),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _isRunning ? null : _showPreTestDialog,
                        child: _GlassCard(
                          borderGlow: _isRunning
                              ? Colors.transparent
                              : Colors.greenAccent.withOpacity(0.3),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.power_settings_new,
                                    color: _isRunning
                                        ? Colors.grey
                                        : Colors.greenAccent),
                                const SizedBox(width: 8),
                                Text(
                                  'TESTİ BAŞLAT',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color:
                                        _isRunning ? Colors.grey : Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isRunning ? _stopTest : null,
                        child: _GlassCard(
                          borderGlow: _isRunning
                              ? Colors.redAccent.withOpacity(0.3)
                              : Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.stop_circle,
                                    color: !_isRunning
                                        ? Colors.grey
                                        : Colors.redAccent),
                                const SizedBox(width: 8),
                                Text(
                                  'TESTİ BİTİR',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: !_isRunning
                                        ? Colors.grey
                                        : Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: _GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: _finalRmsAv == null
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.dashboard_customize_outlined,
                                      size: 32, color: Colors.blueGrey),
                                  SizedBox(height: 8),
                                  Text(
                                    'VERİ AKIŞI BEKLENİYOR..',
                                    style: TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0),
                                  ),
                                ],
                              ),
                            )
                          : _buildGaugeResults(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                    flex: 3,
                    child: _GlassCard(
                        child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('GÜZERGAH & MESAFE',
                                        style: TextStyle(
                                            color: Colors.blueGrey,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                    Row(children: [
                                      if (_sessionAnomalies.isNotEmpty) ...[
                                        const Icon(Icons.warning_amber_rounded,
                                            color: Color(0xFFFF3131), size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                            'Anomali: ${_sessionAnomalies.length}',
                                            style: const TextStyle(
                                                color: Color(0xFFFF3131),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12)),
                                        const SizedBox(width: 12),
                                      ],
                                      Text(
                                          '${_totalDistanceKm.toStringAsFixed(2)} km  •  $_durationSeconds sn',
                                          style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12))
                                    ])
                                  ]),

                              // ---- YENİ EKLENEN CANLI HIZ PANELİ ----
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color:
                                            Colors.blueGrey.withOpacity(0.2))),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        'Anlık: ${_currentSpeedKmh.toStringAsFixed(1)} km/sa',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        'Ortalama: ${_averageSpeedKmh.toStringAsFixed(1)} km/s',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11)),
                                    Text(
                                        'Sapma: ±${_speedDeviation.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              // ---------------------------------------

                              const SizedBox(height: 12),
                              Expanded(
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _buildMap())),
                            ])))),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: _GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ZAMAN BAZLI DEĞİŞİM GRAFİĞİ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                        letterSpacing: 1.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Zaman Serisi R.S.S Spektrumu (${_chartData.length} pts)',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.blueGrey.shade300),
                                  )
                                ],
                              ),
                              if (_isRunning)
                                FadeTransition(
                                  opacity: _pulseAnimation,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                            color: Colors.redAccent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.redAccent,
                                                  blurRadius: 4,
                                                  spreadRadius: 1)
                                            ]),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('REC',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.redAccent,
                                              letterSpacing: 1.5)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: LineChart(
                              LineChartData(
                                minY: 0,
                                maxY: 10,
                                minX: minX,
                                maxX: maxX,
                                lineTouchData:
                                    const LineTouchData(enabled: false),
                                gridData: const FlGridData(
                                  show: false,
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      getTitlesWidget: (value, meta) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8.0),
                                        child: Text(
                                          value.toInt().toString(),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              color: Colors.blueGrey.shade400,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                  bottomTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _chartData,
                                    isCurved: true,
                                    curveSmoothness: 0.35,
                                    color: const Color(0xFF39FF14),
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFF39FF14)
                                              .withOpacity(0.35),
                                          const Color(0xFF39FF14)
                                              .withOpacity(0.01),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              duration: Duration.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeResults() {
    final double rms = _finalRmsAv ?? 0.0;
    final (label, color) = _getComfortLabel(rms);

    return Column(
      children: [
        const Text(
          'OVERALL RIDE VALUE (COMFORT SCORE)',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 1.5),
        ),
        const Spacer(),
        SizedBox(
          height: 90,
          width: 150,
          child: CustomPaint(
            painter: _ArcGaugePainter(value: rms, maxLimit: 4.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  rms.toStringAsFixed(3),
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
                const Text(
                  'm/s²',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color borderGlow;

  const _GlassCard({required this.child, this.borderGlow = Colors.transparent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderGlow == Colors.transparent
                  ? Colors.white.withOpacity(0.1)
                  : borderGlow,
              width: 1.5,
            ),
            boxShadow: borderGlow != Colors.transparent
                ? [
                    BoxShadow(
                        color: borderGlow.withOpacity(0.2),
                        blurRadius: 16,
                        spreadRadius: 2)
                  ]
                : [],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double value;
  final double maxLimit;

  _ArcGaugePainter({required this.value, required this.maxLimit});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height),
      width: size.width,
      height: size.height * 2,
    );

    const double startAngle = pi;
    const double sweepAngle = pi;

    final Paint bgPaint = Paint()
      ..color = Colors.blueGrey.withOpacity(0.1)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    final Paint activePaint = Paint()
      ..shader = const SweepGradient(
        center: Alignment.bottomCenter,
        startAngle: pi,
        endAngle: 2 * pi,
        colors: [
          Colors.greenAccent,
          Colors.yellowAccent,
          Colors.redAccent,
        ],
        stops: [0.0, 0.4, 0.8],
      ).createShader(rect)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double renderedValue = value.clamp(0.0, maxLimit);
    final double activeSweepAngle = (renderedValue / maxLimit) * pi;
    canvas.drawArc(rect, startAngle, activeSweepAngle, false, activePaint);

    final Paint tickPaint = Paint()
      ..color = Colors.blueGrey.withOpacity(0.5)
      ..strokeWidth = 2;
    for (int i = 0; i <= 4; i++) {
      double angle = pi + (i / 4) * pi;
      double radius = size.width / 2;
      Offset start = Offset(size.width / 2 + (radius + 8) * cos(angle),
          size.height + (radius + 8) * sin(angle));
      Offset end = Offset(size.width / 2 + (radius + 16) * cos(angle),
          size.height + (radius + 16) * sin(angle));
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
