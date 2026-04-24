import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  bool _isRunning = false;

  static const int _fftWindowSize = 512;
  static const double _samplingRate = 50.0;
  
  final List<double> _bufferX = [];
  final List<double> _bufferY = [];
  final List<double> _bufferZ = [];
  
  int _tickCount = 0;
  double _timeCounterChart = 0;
  final List<FlSpot> _chartData = [];
  static const int _maxDataPoints = 60;
  
  final List<double> _sessionRmsScores = [];

  double? _gravityX;
  double? _gravityY;
  double? _gravityZ;
  static const double _alpha = 0.1;

  double? _finalRmsAv;
  Position? _currentPosition;

  StreamSubscription<Position>? _positionSubscription;
  final List<LatLng> _routeMap = [];
  double _totalDistanceKm = 0.0;
  DateTime? _testStartTime;
  int _durationSeconds = 0;

  DateTime? _lastAnomalyTime;
  final List<Map<String, dynamic>> _sessionAnomalies = [];

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
                          border:
                              Border.all(color: Colors.blueGrey.withOpacity(0.3)),
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
                          border:
                              Border.all(color: Colors.blueGrey.withOpacity(0.3)),
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
                          border:
                              Border.all(color: Colors.blueGrey.withOpacity(0.3)),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                        color:
                                            Colors.greenAccent.withOpacity(0.5))),
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedPhonePlacement = tempPlacement;
                                });
                                Navigator.pop(context);
                                _startTest();
                              },
                              child: const Text('ONAYLA',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
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
      _bufferX.clear();
      _bufferY.clear();
      _bufferZ.clear();
      _sessionRmsScores.clear();
      _timeCounterChart = 0;
      _tickCount = 0;

      _gravityX = null;
      _gravityY = null;
      _gravityZ = null;
      _currentPosition = null;

      _routeMap.clear();
      _totalDistanceKm = 0.0;
      _testStartTime = DateTime.now();
      _durationSeconds = 0;

      _lastAnomalyTime = null;
      _sessionAnomalies.clear();
    });

    _fetchLocationAndStartStream();

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      if (!_isRunning) return;

      _gravityX = _gravityX == null
          ? event.x
          : _alpha * event.x + (1 - _alpha) * _gravityX!;
      _gravityY = _gravityY == null
          ? event.y
          : _alpha * event.y + (1 - _alpha) * _gravityY!;
      _gravityZ = _gravityZ == null
          ? event.z
          : _alpha * event.z + (1 - _alpha) * _gravityZ!;

      final double dx = event.x - _gravityX!;
      final double dy = event.y - _gravityY!;
      final double dz = event.z - _gravityZ!;

      _bufferX.add(dx);
      _bufferY.add(dy);
      _bufferZ.add(dz);
      _tickCount++;

      if (_bufferX.length > _fftWindowSize) {
        _bufferX.removeAt(0);
        _bufferY.removeAt(0);
        _bufferZ.removeAt(0);
      }

      if (_bufferX.length == _fftWindowSize && _tickCount >= 50) {
        _tickCount = 0;
        _calculateBlockRms();
      }
    });
  }

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
      _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (_currentPosition != null && _isRunning) {
         setState(() {
            _routeMap.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
         });
      }
    } catch (e) {
      debugPrint("Init loc failed: $e");
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((Position position) {
      if (!_isRunning) return;

      if (position.accuracy > 25.0) return;

      final newPoint = LatLng(position.latitude, position.longitude);
      
      if (_routeMap.isNotEmpty && _currentPosition != null) {
         final distance = const Distance().as(LengthUnit.Meter, _routeMap.last, newPoint);
         
         final timeDiff = position.timestamp.difference(_currentPosition!.timestamp).inMilliseconds / 1000.0;
         
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
              _durationSeconds = DateTime.now().difference(_testStartTime!).inSeconds;
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

  double _getWdWeighting(double f) {
    if (f <= 0.0) return 0.0;
    if (f < 0.5) return f / 0.5;
    if (f >= 0.5 && f <= 2.0) return 1.0;
    return 2.0 / f;
  }

  double _getWbWeighting(double f) {
    if (f <= 0.0) return 0.0;
    if (f < 1.0) return 0.5;
    if (f >= 1.0 && f < 4.0) return 0.5 * sqrt(f / 1.0);
    if (f >= 4.0 && f <= 8.0) return 1.0;
    return 8.0 / f;
  }

  void _calculateBlockRms() {
    final fft = FFT(_fftWindowSize);
    final resX = fft.realFft(_bufferX);
    final resY = fft.realFft(_bufferY);
    final resZ = fft.realFft(_bufferZ);

    double sumSqX = 0;
    double sumSqY = 0;
    double sumSqZ = 0;

    final double df = _samplingRate / _fftWindowSize;

    for (int i = 1; i < _fftWindowSize ~/ 2; i++) {
      double f = i * df;

      double magX = sqrt(resX[i].x * resX[i].x + resX[i].y * resX[i].y);
      double magY = sqrt(resY[i].x * resY[i].x + resY[i].y * resY[i].y);
      double magZ = sqrt(resZ[i].x * resZ[i].x + resZ[i].y * resZ[i].y);

      // Energy Density
      double powerX = (magX * magX) * 2 / (_fftWindowSize * _fftWindowSize);
      double powerY = (magY * magY) * 2 / (_fftWindowSize * _fftWindowSize);
      double powerZ = (magZ * magZ) * 2 / (_fftWindowSize * _fftWindowSize);

      double wd = _getWdWeighting(f);
      double wb = _getWbWeighting(f);

      sumSqX += powerX * wd * wd;
      sumSqY += powerY * wd * wd;
      sumSqZ += powerZ * wb * wb;
    }

    double awx = sqrt(sumSqX);
    double awy = sqrt(sumSqY);
    double awz = sqrt(sumSqZ);

    double finalBlockAv = sqrt(awx * awx + awy * awy + awz * awz);

    if (finalBlockAv > 1.25) {
      final now = DateTime.now();
      if (_lastAnomalyTime == null || now.difference(_lastAnomalyTime!).inMilliseconds > 2500) {
        _lastAnomalyTime = now;
        if (_currentPosition != null) {
          _sessionAnomalies.add({
             'lat': _currentPosition!.latitude,
             'lng': _currentPosition!.longitude,
             'timestamp': now.toIso8601String(),
             'peak_score': finalBlockAv
          });
          HapticFeedback.heavyImpact();
        }
      }
    } else if (finalBlockAv > 2.5) {
      HapticFeedback.heavyImpact();
    }

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
    
    _calculateIsoComfort();
  }

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
      'start_lat': startLat,
      'start_lng': startLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'anomaly_count': _sessionAnomalies.length,
      'vehicle_info': _vehicleInfoController.text.trim().isEmpty ? null : _vehicleInfoController.text.trim(),
      'tire_info': _tireInfoController.text.trim().isEmpty ? null : _tireInfoController.text.trim(),
      'phone_placement': _selectedPhonePlacement,
      'route_points': jsonEncode(_routeMap.map((ll) => {'lat': ll.latitude, 'lng': ll.longitude}).toList())
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
          child: Text('GPS Sinyali Bekleniyor...', style: TextStyle(color: Colors.blueGrey)),
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
             colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.darken),
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
                  child: const Icon(Icons.circle, color: Colors.blueAccent, size: 14),
                ),
              if (_routeMap.length > 1)
                Marker(
                  point: _routeMap.last,
                  width: 20,
                  height: 20,
                  child: const Icon(Icons.my_location, color: Color(0xFF39FF14), size: 16),
                ),
              ..._sessionAnomalies.map((a) {
                return Marker(
                  point: LatLng(a['lat'], a['lng']),
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                         BoxShadow(color: const Color(0xFFFF3131).withOpacity(0.5), blurRadius: 12, spreadRadius: 4)
                      ]
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3131), size: 28),
                  )
                );
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
                      child: Column(
                        children: [
                           Row(
                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                             children: [
                               const Text('GÜZERGAH & MESAFE', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12)),
                               Row(
                                 children: [
                                    if (_sessionAnomalies.isNotEmpty) ...[
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3131), size: 14),
                                      const SizedBox(width: 4),
                                      Text('Anomali: ${_sessionAnomalies.length}', style: const TextStyle(color: Color(0xFFFF3131), fontWeight: FontWeight.bold, fontSize: 12)),
                                      const SizedBox(width: 12),
                                    ],
                                    Text('${_totalDistanceKm.toStringAsFixed(2)} km  •  $_durationSeconds sn', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12))
                                 ]
                               )
                             ]
                           ),
                           const SizedBox(height: 12),
                           Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _buildMap())),
                        ]
                      )
                    )
                  )
                ),
                
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
                                lineTouchData: const LineTouchData(enabled: false),
                                gridData: const FlGridData(
                                  show: false,
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      getTitlesWidget: (value, meta) => Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
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
                                          const Color(0xFF39FF14).withOpacity(0.35),
                                          const Color(0xFF39FF14).withOpacity(0.01),
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
