import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fftea/fftea.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'iso_comfort_screen.dart';
import 'splash_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Varsayılan .env dosyası bulunamadı, AI modülü çalışmayabilir.");
  }
  runApp(const KonforOlcerApp());
}

class KonforOlcerApp extends StatelessWidget {
  const KonforOlcerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ride Comfort',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
          useMaterial3: true),

      home: const SplashScreen(),
    );
  }
}

class SensorEkrani extends StatefulWidget {
  const SensorEkrani({super.key});
  @override
  State<SensorEkrani> createState() => _SensorEkraniState();
}

class _SensorEkraniState extends State<SensorEkrani> {
  List<double> _ivme = [0.0, 0.0, 0.0];
  final List<StreamSubscription> _subscriptions = [];

  final List<String> _hamVeriListesi = [];
  String _sonFFTTablosu = "";

  double? _baslangicZamani;

  static const int fftPencere = 256;
  static const double orneklemeHizi = 50.0;

  final List<double> _bufX = [], _bufY = [], _bufZ = [];
  List<FlSpot> _spotsX = [], _spotsY = [], _spotsZ = [];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20))
          .listen((event) {
        setState(() => _ivme = [event.x, event.y, event.z]);

        final suAnkiSaniye = DateTime.now().millisecondsSinceEpoch / 1000.0;
        _baslangicZamani ??= suAnkiSaniye;
        final gecenSaniye = suAnkiSaniye - _baslangicZamani!;

        _hamVeriListesi.add(
            "${gecenSaniye.toStringAsFixed(3)};${event.x};${event.y};${event.z}");

        _bufX.add(event.x);
        _bufY.add(event.y);
        _bufZ.add(event.z);

        if (_bufZ.length >= fftPencere) {
          _hesaplaFFT();
          _bufX.clear();
          _bufY.clear();
          _bufZ.clear();
        }
      }),
    );
  }

  void _hesaplaFFT() {
    final fft = FFT(fftPencere);
    final resX = fft.realFft(_bufX);
    final resY = fft.realFft(_bufY);
    final resZ = fft.realFft(_bufZ);

    List<FlSpot> sX = [], sY = [], sZ = [];
    String yeniFftTablo = "";

    for (int i = 0; i < fftPencere / 2; i++) {
      double hz = i * (orneklemeHizi / fftPencere);

      double fftX =
          math.sqrt((resX[i].x * resX[i].x) + (resX[i].y * resX[i].y));
      double fftY =
          math.sqrt((resY[i].x * resY[i].x) + (resY[i].y * resY[i].y));
      double fftZ =
          math.sqrt((resZ[i].x * resZ[i].x) + (resZ[i].y * resZ[i].y));

      if (i == 0) {
        fftX = 0;
        fftY = 0;
        fftZ = 0;
      }

      sX.add(FlSpot(hz, fftX));
      sY.add(FlSpot(hz, fftY));
      sZ.add(FlSpot(hz, fftZ));

      yeniFftTablo += "$hz;$fftX;$fftY;$fftZ\n";
    }

    setState(() {
      _spotsX = sX;
      _spotsY = sY;
      _spotsZ = sZ;
      _sonFFTTablosu = yeniFftTablo;
    });
  }

  Future<void> _paylas() async {
    if (_hamVeriListesi.isEmpty) return;

    String csvIcerik =
        "Zaman(s);Ivme_X(m/s^2);Ivme_Y(m/s^2);Ivme_Z(m/s^2);Frekans(Hz);FFT_X;FFT_Y;FFT_Z\n";

    List<String> fftSatirlari = _sonFFTTablosu.split("\n");
    if (fftSatirlari.isNotEmpty && fftSatirlari.last.isEmpty) {
      fftSatirlari.removeLast();
    }

    for (int i = 0; i < _hamVeriListesi.length; i++) {
      String hamSatir = _hamVeriListesi[i];
      String fftSatir = (i < fftSatirlari.length)
          ? fftSatirlari[i]
          : ";;;"; 

      csvIcerik += "$hamSatir;$fftSatir\n";
    }

    csvIcerik = csvIcerik.replaceAll('.', ',');

    try {
      final dir = await getTemporaryDirectory();
      final dosya = await File('${dir.path}/Ivme_ve_Frekans_Verileri.csv')
          .writeAsString(csvIcerik);

      await Share.shareXFiles([XFile(dosya.path)],
          text: 'İvme ve FFT(Hz) Verileri');
    } catch (e) {
      debugPrint("Paylaşım hatası: $e");
    }
  }

  @override
  void dispose() {
    for (var s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Konfor Ölçer",
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _paylas,
            icon: const Icon(Icons.share),
            tooltip: 'Verileri İlet',
          )
        ],
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _card("Anlık İvme (m/s²)",
              "X: ${_ivme[0].toStringAsFixed(2)}   Y: ${_ivme[1].toStringAsFixed(2)}   Z: ${_ivme[2].toStringAsFixed(2)}"),
          const SizedBox(height: 10),
          Text("Toplanan Satır Sayısı: ${_hamVeriListesi.length}",
              style: TextStyle(
                  color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _grafik("X Ekseni (Hz)", _spotsX, Colors.blue),
          _grafik("Y Ekseni (Hz)", _spotsY, Colors.green),
          _grafik("Z Ekseni (Hz)", _spotsZ, Colors.pink),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _card(String t, String v) => Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          const Icon(Icons.speed, color: Colors.pink, size: 30),
          const SizedBox(height: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(v,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ]),
      ));

  Widget _grafik(String t, List<FlSpot> s, Color c) => Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          Text(t,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          SizedBox(
              height: 120,
              child: s.isEmpty
                  ? Center(child: CircularProgressIndicator(color: c))
                  : LineChart(LineChartData(
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                          LineChartBarData(
                              spots: s,
                              color: c,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                  show: true, color: c.withOpacity(0.1)))
                        ]))),
        ]),
      ));
}
