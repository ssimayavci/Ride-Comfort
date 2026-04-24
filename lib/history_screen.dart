import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'database_helper.dart';
import 'ai_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _testsFuture;

  @override
  void initState() {
    super.initState();
    _refreshTests();
  }

  void _refreshTests() {
    setState(() {
      _testsFuture = DatabaseHelper.instance.readAllTests();
    });
  }

  (String, Color) _getComfortLabel(double rms) {
    if (rms < 0.315) return ("Çok rahat", Colors.greenAccent);
    if (rms < 0.63) return ("Biraz rahatsız", Colors.lightGreenAccent);
    if (rms < 1.0) return ("Oldukça rahatsız", Colors.orangeAccent);
    if (rms < 1.6) return ("Rahatsız", Colors.deepOrangeAccent);
    if (rms < 2.5) return ("Çok rahatsız", Colors.redAccent);
    return ("Aşırı rahatsız", Colors.red);
  }

  Future<void> _showTestDetails(
      Map<String, dynamic> test, String testTitle) async {
    List<Map<String, dynamic>> anomalies =
        await DatabaseHelper.instance.readAnomaliesForTest(test['id']);

    List<LatLng> routePoints = [];
    if (test['route_points'] != null) {
      try {
        final List<dynamic> pointsArray = jsonDecode(test['route_points']);
        routePoints =
            pointsArray.map((p) => LatLng(p['lat'], p['lng'])).toList();
      } catch (e) {
        debugPrint('Error parsing route_points: \$e');
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final double score = test['score'];
        final (label, color) = _getComfortLabel(score);
        final DateTime dt = DateTime.parse(test['timestamp']);
        final String formattedDate =
            "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

        String? aiErrorMessage;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: _GlassCard(
                borderGlow: color.withOpacity(0.5),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      testTitle,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'RMS DEĞERİ: ${score.toStringAsFixed(3)} m/s²',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: color),
                    ),
                    const SizedBox(height: 8),
                    Text(label.toUpperCase(),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 32),
                    _buildDetailRow(
                        Icons.calendar_today, 'Tarih', formattedDate),
                    if (test['vehicle_info'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          Icons.directions_car, 'Araç', test['vehicle_info']),
                    ],
                    if (test['tire_info'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          Icons.settings, 'Lastik', test['tire_info']),
                    ],
                    if (test['phone_placement'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.smartphone_outlined,
                          'Telefon Konumu', test['phone_placement']),
                    ],
                    if (test['anomaly_count'] != null &&
                        test['anomaly_count'] > 0) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          Icons.warning_amber_rounded,
                          'Tespit Edilen Anomali',
                          '${test['anomaly_count']} Adet'),
                    ],
                    if (test['distance_km'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.route, 'Mesafe',
                          '${test['distance_km']!.toStringAsFixed(2)} km'),
                    ],
                    if (test['duration_seconds'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.timer, 'Süre',
                          '${test['duration_seconds']} sn'),
                    ],
                    const SizedBox(height: 12),
                    _buildDetailRow(
                        Icons.location_on,
                        'Başlangıç Konumu',
                        test['start_lat'] != null
                            ? '${test['start_lat']!.toStringAsFixed(4)}, ${test['start_lng']!.toStringAsFixed(4)}'
                            : 'Konum bulunamadı'),
                    if (test['end_lat'] != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.flag, 'Bitiş Konumu',
                          '${test['end_lat']!.toStringAsFixed(4)}, ${test['end_lng']!.toStringAsFixed(4)}'),
                    ],
                    const SizedBox(height: 24),
                    if (routePoints.isNotEmpty) ...[
                      SizedBox(
                        height: 200,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: routePoints.first,
                              initialZoom: 15.0,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.all,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.simay.konfor_olcer',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: routePoints,
                                    color: Colors.blueAccent,
                                    strokeWidth: 4.0,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: anomalies
                                    .map((a) => Marker(
                                          point: LatLng(a['lat'], a['lng']),
                                          width: 30,
                                          height: 30,
                                          child: const Icon(Icons.location_on,
                                              color: Colors.redAccent,
                                              size: 30),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (aiErrorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Text(
                          aiErrorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigoAccent.withOpacity(0.2),
                          foregroundColor: Colors.indigoAccent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: Colors.indigoAccent.withOpacity(0.5))),
                        ),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('🤖 YZ Analizi Raporu Al',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          setDialogState(() {
                            aiErrorMessage = null;
                          });
                          try {
                            await _generateAiReport(test);
                          } catch (e) {
                            setDialogState(() {
                              aiErrorMessage = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('KAPAT'),
                      ),
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

  Future<void> _generateAiReport(Map<String, dynamic> test) async {
    // 1. KONTROL: Rapor daha önce alınmış ve kaydedilmişse API'ye hiç gitme!
    if (test.containsKey('ai_report') &&
        test['ai_report'] != null &&
        test['ai_report'].toString().isNotEmpty) {
      _showReportDialog(test['ai_report']); // Doğrudan hafızadaki raporu göster
      return;
    }

    // Yükleme animasyonunu göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.indigoAccent),
      ),
    );

    try {
      final int sessionId = test['id'];
      List<Map<String, dynamic>> anomalies = [];
      if (test['anomaly_count'] != null && test['anomaly_count'] > 0) {
        anomalies =
            await DatabaseHelper.instance.readAnomaliesForTest(sessionId);
      }

      // API'ye istek at
      final String report =
          await AiService.generateRideAnalysis(test, anomalies);

      if (context.mounted) {
        Navigator.pop(context); // Yükleme animasyonunu kapat

        if (report.contains("KOTA AŞILDI")) {
          throw Exception("KOTA AŞILDI: Google sunucularına çok fazla istek gönderildi. Lütfen yaklaşık 30 saniye bekleyip tekrar deneyin.");
        } else if (report.startsWith("⚠️ **HATA**")) {
          throw Exception("BEKLENMEYEN HATA: $report");
        } else {
          // --- İŞTE EKSİK OLAN SİHİRLİ KISIM BURASIYDI ---
          // Rapor başarılıysa bunu veritabanına ve o anki test verisine yazıyoruz!
          try {
            await DatabaseHelper.instance.saveAiReport(test['id'], report);
            test['ai_report'] = report;
          } catch (e) {
            debugPrint("Rapor veritabanına kaydedilemedi: $e");
          }
          // -----------------------------------------------

          // Normal raporu göster
          _showReportDialog(report);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        rethrow;
      }
    }
  }

  void _showReportDialog(String markdownContent) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: _GlassCard(
            borderGlow: Colors.indigoAccent.withOpacity(0.6),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory, color: Colors.indigoAccent, size: 28),
                      SizedBox(width: 12),
                      Text(
                        "UZMAN ANALİZİ",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  Flexible(
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: markdownContent,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                              color: Colors.white70, fontSize: 14, height: 1.5),
                          strong: const TextStyle(
                              color: Colors.indigoAccent,
                              fontWeight: FontWeight.bold),
                          listBullet:
                              const TextStyle(color: Colors.indigoAccent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('KAPAT'),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        )
      ],
    );
  }

  Future<void> _exportToCsv(List<Map<String, dynamic>> tests) async {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Rapor Hazırlanıyor...',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );

    List<List<dynamic>> rows = [];
    rows.add([
      "Test",
      "Tarih",
      "Saat",
      "Araç Bilgisi",
      "Lastik Bilgisi",
      "Telefon Konumu",
      "Mesafe (km)",
      "Süre (sn)",
      "Bas. Enlem",
      "Bas. Boylam",
      "Bitis Enlem",
      "Bitis Boylam",
      "RMS Konfor Skoru",
      "Durum",
      "Toplam Anomali"
    ]);

    for (var test in tests) {
      final double score = test['score'];
      final (label, _) = _getComfortLabel(score);
      final DateTime dt = DateTime.parse(test['timestamp']);
      final String formattedDate = "${dt.month}/${dt.day}/${dt.year}";
      final String formattedTime =
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

      rows.add([
        'Test Kaydı',
        formattedDate,
        formattedTime,
        test['vehicle_info'] ?? 'N/A',
        test['tire_info'] ?? 'N/A',
        test['phone_placement'] ?? 'N/A',
        test['distance_km']?.toStringAsFixed(3) ?? 'N/A',
        test['duration_seconds']?.toString() ?? 'N/A',
        test['start_lat']?.toStringAsFixed(5) ??
            test['latitude']?.toStringAsFixed(5) ??
            'N/A', // Fallback for V1
        test['start_lng']?.toStringAsFixed(5) ??
            test['longitude']?.toStringAsFixed(5) ??
            'N/A',
        test['end_lat']?.toStringAsFixed(5) ?? 'N/A',
        test['end_lng']?.toStringAsFixed(5) ?? 'N/A',
        score.toStringAsFixed(4),
        label,
        test['anomaly_count']?.toString() ?? '0'
      ]);

      if (test['anomaly_count'] != null && test['anomaly_count'] > 0) {
        rows.add(["-> GÜZERGAH ANOMALİLERİ (ALT LİSTE)"]);
        rows.add(["Anomaly_Lat", "Anomaly_Lng", "Peak_Score", "Timestamp"]);

        final int sessionId = test['id'];
        final anomalies =
            await DatabaseHelper.instance.readAnomaliesForTest(sessionId);
        for (var a in anomalies) {
          rows.add([
            a['lat']?.toStringAsFixed(5) ?? 'N/A',
            a['lng']?.toStringAsFixed(5) ?? 'N/A',
            (a['peak_score'] as double?)?.toStringAsFixed(4) ?? 'N/A',
            a['timestamp'] ?? 'N/A'
          ]);
        }
        rows.add([]);
      }
    }

    String finalCsvString =
        rows.map((row) => row.map((item) => '"$item"').join(',')).join('\n');

    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final String timestampStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final String path = "${dir.path}/Ride_Comfort_Report_$timestampStr.csv";

    final File file = File(path);
    await file.writeAsString(finalCsvString);

    await Share.shareXFiles([XFile(path)], text: 'Sürüş Konforu Analiz Raporu');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('TEST GEÇMİŞİ',
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
            icon: const Icon(Icons.file_download, color: Colors.blueGrey),
            onPressed: () async {
              final tests = await _testsFuture;
              if (tests.isNotEmpty) {
                await _exportToCsv(tests);
              }
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
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _testsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Colors.lightBlueAccent));
              } else if (snapshot.hasError) {
                return Center(
                    child: Text('Geçmiş yüklenirken hata oluştu.',
                        style: const TextStyle(color: Colors.redAccent)));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off,
                          color: Colors.blueGrey, size: 64),
                      SizedBox(height: 16),
                      Text('Kayıtlı test bulunamadı.',
                          style:
                              TextStyle(color: Colors.blueGrey, fontSize: 16)),
                    ],
                  ),
                );
              }

              final tests = snapshot.data!;
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: tests.length,
                itemBuilder: (context, index) {
                  final test = tests[index];
                  final double score = test['score'];
                  final (label, color) = _getComfortLabel(score);
                  final DateTime dt = DateTime.parse(test['timestamp']);

                  final String testTitle = 'Test ${tests.length - index}';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Dismissible(
                      key: Key(test['id'].toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.redAccent, width: 1),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24.0),
                        child: const Icon(Icons.delete_sweep,
                            color: Colors.white, size: 32),
                      ),
                      onDismissed: (direction) async {
                        await DatabaseHelper.instance.deleteTest(test['id']);
                        _refreshTests();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Test kaydı silindi.',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              backgroundColor: Colors.redAccent.shade700,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              action: SnackBarAction(
                                label: 'GERİ AL',
                                textColor: Colors.white,
                                onPressed: () async {
                                  await DatabaseHelper.instance
                                      .insertTest(test);
                                  _refreshTests();
                                },
                              ),
                            ),
                          );
                        }
                      },
                      child: GestureDetector(
                        onTap: () => _showTestDetails(test, testTitle),
                        child: _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: color.withOpacity(0.5),
                                        width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      score.toStringAsFixed(1),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        testTitle,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} - $label${(test['anomaly_count'] != null && test['anomaly_count'] > 0) ? " • ${test['anomaly_count']} Anomali" : ""}',
                                        style: TextStyle(
                                            color: Colors.blueGrey.shade300,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share,
                                      color: Colors.blueGrey, size: 20),
                                  onPressed: () => _exportToCsv([test]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
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
