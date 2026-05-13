import 'dart:async';
import 'dart:collection'; // NEW: Queue for O(1) sliding-window front-removal
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart'; // NEW: compute() for background isolate
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
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_helper.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TOP-LEVEL SECTION — ISO 2631-1 CONSTANTS, HELPERS & COMPUTE ENTRY POINT
//
// Everything in this section must live OUTSIDE any class so that Flutter's
// compute() helper can dispatch _computeRmsBlock() to a background Isolate
// without capturing instance state (which would cause a serialisation error).
// ═══════════════════════════════════════════════════════════════════════════

/// ISO 2631-1 one-third octave band centre frequencies (Hz).
const List<double> _kIsoFreqs = [
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
  400.0,
];

/// Wk weighting factors — vertical Z axis (ISO 2631-1 Table A.2).
const List<double> _kWkRaw = [
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
  0.00195,
];

/// Wd weighting factors — horizontal X/Y axes (ISO 2631-1 Table A.2).
const List<double> _kWdRaw = [
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
  0.00031,
];

/// Equivalent of numpy.interp — piecewise linear interpolation on sorted
/// (xp, fp) pairs. Clamps at the boundary values outside [xp.first, xp.last].
double _interpIso(double x, List<double> xp, List<double> fp) {
  if (x <= xp.first) return fp.first;
  if (x >= xp.last) return fp.last;
  for (int i = 0; i < xp.length - 1; i++) {
    if (x >= xp[i] && x <= xp[i + 1]) {
      final double t = (x - xp[i]) / (xp[i + 1] - xp[i]);
      return fp[i] + t * (fp[i + 1] - fp[i]);
    }
  }
  return 0.0;
}

/// Returns the Wd weighting coefficient for frequency [f] (horizontal axes).
double _getWdWeight(double f) => _interpIso(f, _kIsoFreqs, _kWdRaw);

/// Returns the Wk weighting coefficient for frequency [f] (vertical axis).
double _getWkWeight(double f) => _interpIso(f, _kIsoFreqs, _kWkRaw);

/// ─────────────────────────────────────────────────────────────────────────
/// Entry point for Flutter's [compute] helper.
///
/// Receives a plain [Map] (safe to copy across the isolate boundary) and
/// returns a plain [Map] with the computed results.
///
/// INPUT keys:
///   bufX / bufY / bufZ  — List<double> snapshots of the 512-sample window
///   timeBuf             — List<double> elapsed-time stamps (seconds)
///   N                   — FFT window size (int, currently 512)
///   testElapsedMs       — milliseconds elapsed since test start (double)
///   needsValidation     — bool; true only for the very first FFT block
///
/// OUTPUT keys:
///   finalBlockAv   — double  Overall Vibration Value (OVV) for this block
///   fftCsvRows     — List<String>  FFT rows ready for direct IOSink writes
///   isAnomaly      — bool    true when finalBlockAv > 1.25 m/s²
///   validationRows — List<String>  non-empty only when needsValidation=true
/// ─────────────────────────────────────────────────────────────────────────
Map<String, dynamic> _computeRmsBlock(Map<String, dynamic> params) {
  final List<double> bufX = List<double>.from(params['bufX'] as List);
  final List<double> bufY = List<double>.from(params['bufY'] as List);
  final List<double> bufZ = List<double>.from(params['bufZ'] as List);
  final List<double> timeBuf = List<double>.from(params['timeBuf'] as List);
  final int N = params['N'] as int;
  final double testElapsedMs = (params['testElapsedMs'] as num).toDouble();
  final bool needsValidation = params['needsValidation'] as bool;

  // ── 1. DC REMOVAL (zero-mean / detrending) ────────────────────────────
  // Computed on a temporary copy so the original snapshot is preserved for
  // validation CSV output below.
  final double meanX = bufX.reduce((a, b) => a + b) / N;
  final double meanY = bufY.reduce((a, b) => a + b) / N;
  final double meanZ = bufZ.reduce((a, b) => a + b) / N;

  final List<double> detX = bufX.map((e) => e - meanX).toList();
  final List<double> detY = bufY.map((e) => e - meanY).toList();
  final List<double> detZ = bufZ.map((e) => e - meanZ).toList();

  // ── 2. HAMMING WINDOW with amplitude correction factor 1.852 ──────────
  // The Hamming window's Coherent Gain ≈ 0.54, so we multiply by 1/0.54
  // ≈ 1.852 to restore the physical amplitude of the signal.
  final List<double> winX = List.generate(
      N, (i) => detX[i] * (0.54 - 0.46 * cos(2 * pi * i / (N - 1))) * 1.852);
  final List<double> winY = List.generate(
      N, (i) => detY[i] * (0.54 - 0.46 * cos(2 * pi * i / (N - 1))) * 1.852);
  final List<double> winZ = List.generate(
      N, (i) => detZ[i] * (0.54 - 0.46 * cos(2 * pi * i / (N - 1))) * 1.852);

  // ── 3. FFT ─────────────────────────────────────────────────────────────
  final fft = FFT(N);
  final resX = fft.realFft(winX);
  final resY = fft.realFft(winY);
  final resZ = fft.realFft(winZ);

  // ── 4. ISO WEIGHTING + PARSEVAL RMS ACCUMULATION ──────────────────────
  // Real-spectrum df is derived from the actual measured sampling rate so
  // that clock drift on the device is automatically corrected.
  final double totalTime = timeBuf.last - timeBuf.first;
  final double realFs = (N - 1) / totalTime;
  final double df = realFs / N;

  double sumSqX = 0, sumSqY = 0, sumSqZ = 0;
  final List<String> fftCsvRows = [];
  final double timeSec = testElapsedMs / 1000.0;

  // Only the positive-frequency bins (Nyquist: 1 … N/2-1).
  for (int i = 1; i < N ~/ 2; i++) {
    final double f = i * df;

    // Complex magnitude → physical amplitude (m/s²) via normalisation.
    final double magX = sqrt(resX[i].x * resX[i].x + resX[i].y * resX[i].y);
    final double magY = sqrt(resY[i].x * resY[i].x + resY[i].y * resY[i].y);
    final double magZ = sqrt(resZ[i].x * resZ[i].x + resZ[i].y * resZ[i].y);
    final double ampX = magX / (N / 2);
    final double ampY = magY / (N / 2);
    final double ampZ = magZ / (N / 2);

    // Build CSV row; bin i=1 carries the block timestamp.
    if (i == 1) {
      fftCsvRows.add(
          "${timeSec.toStringAsFixed(3)};;;;${f.toStringAsFixed(2)};${ampX.toStringAsFixed(4)};${ampY.toStringAsFixed(4)};${ampZ.toStringAsFixed(4)}");
    } else {
      fftCsvRows.add(
          ";;;;${f.toStringAsFixed(2)};${ampX.toStringAsFixed(4)};${ampY.toStringAsFixed(4)};${ampZ.toStringAsFixed(4)}");
    }

    // ISO 2631-1 frequency weighting.
    final double wd = _getWdWeight(f);
    final double wk = _getWkWeight(f);
    final double wX = ampX * wd;
    final double wY = ampY * wd;
    final double wZ = ampZ * wk;

    // Parseval's theorem: power = (amplitude²) / 2 for single-sided spectrum.
    sumSqX += (wX * wX) / 2.0;
    sumSqY += (wY * wY) / 2.0;
    sumSqZ += (wZ * wZ) / 2.0;
  }

  // Per-axis RMS → three-axis OVV (Overall Vibration Value).
  final double rmsX = sqrt(sumSqX);
  final double rmsY = sqrt(sumSqY);
  final double rmsZ = sqrt(sumSqZ);
  final double finalBlockAv = sqrt(rmsX * rmsX + rmsY * rmsY + rmsZ * rmsZ);

  // ── 5. VALIDATION ROWS — first block only, for MATLAB export ──────────
  final List<String> validationRows = [];
  if (needsValidation) {
    const double realFsV = 50.0;
    final double dfV = realFsV / N;
    validationRows
        .add("Zaman_s;Ivme_X;Ivme_Y;Ivme_Z;Frekans_Hz;FFT_X;FFT_Y;FFT_Z");
    for (int i = 0; i < N; i++) {
      final String tStr = (i * (1.0 / realFsV)).toStringAsFixed(3);
      final String rawX = bufX[i].toStringAsFixed(4);
      final String rawY = bufY[i].toStringAsFixed(4);
      final String rawZ = bufZ[i].toStringAsFixed(4);
      if (i < N ~/ 2) {
        final double f = i * dfV;
        final double mX = sqrt(resX[i].x * resX[i].x + resX[i].y * resX[i].y);
        final double mY = sqrt(resY[i].x * resY[i].x + resY[i].y * resY[i].y);
        final double mZ = sqrt(resZ[i].x * resZ[i].x + resZ[i].y * resZ[i].y);
        validationRows.add(
            "$tStr;$rawX;$rawY;$rawZ;${f.toStringAsFixed(2)};${(mX / (N / 2)).toStringAsFixed(4)};${(mY / (N / 2)).toStringAsFixed(4)};${(mZ / (N / 2)).toStringAsFixed(4)}");
      } else {
        validationRows.add("$tStr;$rawX;$rawY;$rawZ;;;;");
      }
    }
  }

  return {
    'finalBlockAv': finalBlockAv,
    'fftCsvRows': fftCsvRows,
    'isAnomaly': finalBlockAv > 1.25,
    'validationRows': validationRows,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class IsoComfortScreen extends StatefulWidget {
  const IsoComfortScreen({super.key});

  @override
  State<IsoComfortScreen> createState() => _IsoComfortScreenState();
}

class _IsoComfortScreenState extends State<IsoComfortScreen> {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // Validation rows (bounded: first FFT block only, ≤ 769 strings).
  final List<String> _validationRows = [];

  bool _isRunning = false;

  /// Guards against dispatching a new isolate before the previous one returns.
  /// Without this, rapid ticks could stack multiple concurrent compute() calls.
  bool _isProcessingFft = false;

  static const int _fftWindowSize = 512;
  static const double _samplingRate = 50.0;

  /// Distance threshold (metres) that triggers a hazard voice alert.
  static const double _hazardProximityMeters = 50.0;

  /// Minimum seconds that must elapse before the same hazard fires again.
  static const int _alertCooldownSeconds = 60;

  // ── CHANGE 1: Queue<double> replaces List<double> ──────────────────────
  // Queue.removeFirst() / addLast() are O(1) vs List.removeAt(0) which is
  // O(n). At 50 Hz with a 512-element window that was 76 800 element copies
  // per second — now it's zero.
  final Queue<double> _bufferX = Queue();
  final Queue<double> _bufferY = Queue();
  final Queue<double> _bufferZ = Queue();
  final Queue<double> _timeBuffer = Queue();

  int _tickCount = 0;
  double _timeCounterChart = 0;
  final List<FlSpot> _chartData = [];
  static const int _maxDataPoints = 60;

  // Session-level RMS scores — one entry per ~1 s FFT block.
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

  double _currentSpeedKmh = 0.0;
  double _averageSpeedKmh = 0.0;
  double _speedDeviation = 0.0;
  final List<double> _speedHistory = [];

  // ── CHANGE 2: IOSink replaces unbounded List<String> _machineDataRows ──
  // Rows are streamed directly to disk as they arrive, so RAM usage stays
  // flat regardless of session length.
  IOSink? _csvSink;

  // ── Wakelock + live stopwatch ─────────────────────────────────────────────
  // Timer fires every second while a test is running; _elapsedSeconds drives
  // the MM:SS display and is reset to zero each time a new test starts.
  Timer? _stopwatchTimer;
  int _elapsedSeconds = 0;

  // ── Phase 3: Proactive Hazard Assistant ───────────────────────────────────
  final FlutterTts _tts = FlutterTts();

  /// Full list of global_hazards loaded from DB at app start and refreshed at
  /// the beginning of each test so newly recorded hazards are always current.
  List<Map<String, dynamic>> _globalHazards = [];

  /// Last alert timestamp per hazard id — enforces the 60-second cooldown so
  /// a single rough patch doesn't spam the driver repeatedly.
  final Map<int, DateTime> _hazardAlertTimes = {};

  /// True while the proximity warning banner is being displayed.
  bool _isHazardWarningActive = false;

  /// Toggled by [_hazardBlinkTimer] to produce a pulsing opacity effect.
  bool _hazardWarningVisible = false;

  /// Dismisses the warning banner after 5 seconds.
  Timer? _hazardWarningTimer;

  /// Flips [_hazardWarningVisible] every 500 ms for the blink animation.
  Timer? _hazardBlinkTimer;

  final TextEditingController _vehicleInfoController = TextEditingController();
  final TextEditingController _tireInfoController = TextEditingController();
  String _selectedPhonePlacement = "Yolcu Koltuğu";

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadGlobalHazards();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _vehicleInfoController.dispose();
    _tireInfoController.dispose();
    _stopwatchTimer?.cancel();
    _hazardBlinkTimer?.cancel();
    _hazardWarningTimer?.cancel();
    // Safety net: release wakelock, stop TTS, and close the sink if disposed mid-test.
    WakelockPlus.disable();
    _tts.stop();
    _accelerometerSubscription?.cancel();
    _positionSubscription?.cancel();
    _csvSink?.close();
    super.dispose();
  }

  /// Formats [s] seconds as a zero-padded MM:SS string (e.g. 125 → "02:05").
  String _formatElapsed(int s) {
    final int m = s ~/ 60;
    final int sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('tr-TR');
      await _tts.setSpeechRate(0.45); // Sürüş sırasında netlik için biraz yavaş
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.speak("Sistem hazır Simay, sürüşe başlayabilirsin.");
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  /// Fetches all persisted hazards from the DB into [_globalHazards].
  /// Called once on startup and again at the start of every new test so
  /// hazards recorded during the previous drive are immediately available.
  Future<void> _loadGlobalHazards() async {
    final hazards = await DatabaseHelper.instance.readAllGlobalHazards();
    if (mounted) setState(() => _globalHazards = hazards);
  }

  /// Reads the user's saved default vehicle / tyre info from SharedPreferences
  /// and pre-populates the pre-test dialog controllers.
  /// Called on startup and again whenever the Settings screen is popped.
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final vehicle = prefs.getString(kPrefVehicleInfo) ?? '';
    final tire = prefs.getString(kPrefTireInfo) ?? '';
    // Only update if the user hasn't already typed something in this session.
    if (_vehicleInfoController.text.isEmpty) {
      _vehicleInfoController.text = vehicle;
    }
    if (_tireInfoController.text.isEmpty) {
      _tireInfoController.text = tire;
    }
  }

  /// Called on every GPS position update while a test is running.
  ///
  /// Scans [_globalHazards] with [Geolocator.distanceBetween] (no
  /// approximation — uses Vincenty formula) and fires [_triggerHazardAlert]
  /// when within [_hazardProximityMeters], subject to per-hazard cooldown.
  void _checkHazardProximity(Position position) {
    if (!_isRunning || _globalHazards.isEmpty) return;
    final DateTime now = DateTime.now();
    for (final hazard in _globalHazards) {
      final double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        hazard['lat'] as double,
        hazard['lng'] as double,
      );
      if (dist <= _hazardProximityMeters) {
        final int id = hazard['id'] as int;
        final DateTime? lastAlert = _hazardAlertTimes[id];
        if (lastAlert == null ||
            now.difference(lastAlert).inSeconds >= _alertCooldownSeconds) {
          _hazardAlertTimes[id] = now;
          _triggerHazardAlert(); // async; intentionally fire-and-forget
          return; // one alert at a time — don't stack multiple hazards
        }
      }
    }
  }

  /// Shows the blinking warning banner for 5 seconds and speaks the alert.
  Future<void> _triggerHazardAlert() async {
    _hazardBlinkTimer?.cancel();
    _hazardWarningTimer?.cancel();

    setState(() {
      _isHazardWarningActive = true;
      _hazardWarningVisible = true;
    });

    // Blink every 500 ms — fast enough to be urgent, not so fast it's epileptic.
    _hazardBlinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted)
        setState(() => _hazardWarningVisible = !_hazardWarningVisible);
    });

    // Auto-dismiss after 5 seconds.
    _hazardWarningTimer = Timer(const Duration(seconds: 5), () {
      _hazardBlinkTimer?.cancel();
      _hazardBlinkTimer = null;
      if (mounted) {
        setState(() {
          _isHazardWarningActive = false;
          _hazardWarningVisible = false;
        });
      }
    });

    // Voice alert — non-blocking; TTS handles its own queue internally.
    try {
      await _tts
          .speak('Dikkat, 50 metre sonra bozuk zemin, lütfen yavaşlayın.');
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
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
                                _startTest(); // async; fire-and-forget is fine here
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

  // ── CHANGE 2: async so we can await getTemporaryDirectory() and open
  // the IOSink BEFORE the accelerometer subscription starts writing to it.
  // Everything before the first `await` still runs synchronously (including
  // the setState that flips _isRunning = true), so the UI updates instantly.
  Future<void> _startTest() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isRunning = true;
      _isProcessingFft = false;
      _finalRmsAv = null;
      _chartData.clear();
      _bufferX.clear();
      _bufferY.clear();
      _bufferZ.clear();
      _timeBuffer.clear();
      _sessionRmsScores.clear();
      _validationRows.clear();
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
      _currentSpeedKmh = 0.0;
      _averageSpeedKmh = 0.0;
      _speedDeviation = 0.0;
      _speedHistory.clear();
      _elapsedSeconds = 0;
      _hazardAlertTimes.clear();
      _isHazardWarningActive = false;
      _hazardWarningVisible = false;
    });

    // Refresh hazard list so any hazards recorded in previous sessions are
    // already loaded before the first GPS tick arrives.
    _loadGlobalHazards();

    // Prevent the screen from sleeping while a test is active.
    // WhenInUse location permission is sufficient because wakelock keeps
    // the app in the foreground for the entire session.
    WakelockPlus.enable();

    // Live stopwatch — ticks every second, rebuilds only the timer label.
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && mounted) {
        setState(() => _elapsedSeconds++);
      }
    });

    // Open the streaming CSV file. The await here is negligible in practice
    // (typically < 1 ms) but guarantees the sink is ready before the first
    // accelerometer sample is written.
    final directory = await getTemporaryDirectory();
    final int ts = _testStartTime!.millisecondsSinceEpoch;
    _csvSink = File('${directory.path}/machine_data_$ts.csv').openWrite();
    _csvSink!
        .writeln("Zaman_s;Ivme_X;Ivme_Y;Ivme_Z;Frekans_Hz;FFT_X;FFT_Y;FFT_Z");

    _fetchLocationAndStartStream();

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      if (!_isRunning) return;

      // Low-pass filter to track the static gravity component (alpha = 0.1).
      _gravityX = _gravityX == null
          ? event.x
          : _alpha * event.x + (1 - _alpha) * _gravityX!;
      _gravityY = _gravityY == null
          ? event.y
          : _alpha * event.y + (1 - _alpha) * _gravityY!;
      _gravityZ = _gravityZ == null
          ? event.z
          : _alpha * event.z + (1 - _alpha) * _gravityZ!;

      // Pure vibration = raw reading minus the estimated gravity vector.
      final double dx = event.x - _gravityX!;
      final double dy = event.y - _gravityY!;
      final double dz = event.z - _gravityZ!;

      final double elapsedSeconds = (DateTime.now().millisecondsSinceEpoch -
              _testStartTime!.millisecondsSinceEpoch) /
          1000.0;
      final String time = elapsedSeconds.toStringAsFixed(3);

      // ── CHANGE 2: write raw row directly to disk — no in-memory list ───
      _csvSink?.writeln(
          "$time;${dx.toStringAsFixed(4)};${dy.toStringAsFixed(4)};${dz.toStringAsFixed(4)};;;;;");

      // ── CHANGE 1: O(1) Queue operations ────────────────────────────────
      _timeBuffer.addLast(elapsedSeconds);
      _bufferX.addLast(dx);
      _bufferY.addLast(dy);
      _bufferZ.addLast(dz);
      _tickCount++;

      // Keep the sliding window at exactly _fftWindowSize elements.
      if (_bufferX.length > _fftWindowSize) {
        _bufferX.removeFirst();
        _bufferY.removeFirst();
        _bufferZ.removeFirst();
        _timeBuffer.removeFirst();
      }

      // ── CHANGE 3: _isProcessingFft guard prevents stacked isolate calls ─
      if (_bufferX.length == _fftWindowSize &&
          _tickCount >= 50 &&
          !_isProcessingFft) {
        _tickCount = 0;
        _triggerBlockRms(); // async; intentionally not awaited here
      }
    });
  }

  // ── CHANGE 3: FFT pipeline now runs on a background isolate ─────────────
  // Calling compute() keeps the main thread free for UI rendering while the
  // 512-point FFT + 256 weighted accumulations happen in parallel.
  Future<void> _triggerBlockRms() async {
    _isProcessingFft = true;

    final double testElapsedMs = (DateTime.now().millisecondsSinceEpoch -
            _testStartTime!.millisecondsSinceEpoch)
        .toDouble();

    // Snapshot the Queues into plain Lists before crossing the isolate
    // boundary. toList() is O(n) but happens once per second — cheap.
    final Map<String, dynamic> params = {
      'bufX': _bufferX.toList(),
      'bufY': _bufferY.toList(),
      'bufZ': _bufferZ.toList(),
      'timeBuf': _timeBuffer.toList(),
      'N': _fftWindowSize,
      'testElapsedMs': testElapsedMs,
      'needsValidation': _validationRows.isEmpty,
    };

    final Map<String, dynamic> result = await compute(_computeRmsBlock, params);

    // Guard: the test may have been stopped while the isolate was running.
    if (!_isRunning || !mounted) {
      _isProcessingFft = false;
      return;
    }

    final double finalBlockAv = (result['finalBlockAv'] as num).toDouble();
    final List<String> fftRows = (result['fftCsvRows'] as List).cast<String>();
    final bool isAnomaly = result['isAnomaly'] as bool;
    final List<String> validRows =
        (result['validationRows'] as List).cast<String>();

    // Write FFT rows to the open IOSink on the main thread.
    for (final row in fftRows) {
      _csvSink?.writeln(row);
    }

    // Capture the first-block validation snapshot for MATLAB export.
    if (_validationRows.isEmpty && validRows.isNotEmpty) {
      _validationRows.addAll(validRows);
    }

    // Haptic + anomaly geo-tagging requires GPS position — must be main thread.
    if (isAnomaly) {
      if (finalBlockAv > 2.5) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      final DateTime now = DateTime.now();
      if (_lastAnomalyTime == null ||
          now.difference(_lastAnomalyTime!).inMilliseconds > 2500) {
        _lastAnomalyTime = now;
        if (_currentPosition != null) {
          _sessionAnomalies.add({
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
            'timestamp': now.toIso8601String(),
            'peak_score': finalBlockAv,
          });
          // Persist to the global hazard registry so future drives can warn
          // the driver about this location. Fire-and-forget — the DB write
          // must not block the UI or the FFT dispatch guard.
          unawaited(DatabaseHelper.instance.insertOrUpdateGlobalHazard(
            lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            peakScore: finalBlockAv,
          ));
        }
      }
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

    _isProcessingFft = false;
  }

  // ── CHANGE 2 cont.: async so we can flush/close the IOSink before the
  // final score calculation reads session data.
  Future<void> _stopTest() async {
    if (!_isRunning) return;
    HapticFeedback.lightImpact();

    _stopwatchTimer?.cancel();
    _stopwatchTimer = null;
    _hazardBlinkTimer?.cancel();
    _hazardBlinkTimer = null;
    _hazardWarningTimer?.cancel();
    _hazardWarningTimer = null;
    WakelockPlus.disable();

    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_testStartTime != null) {
      _durationSeconds = DateTime.now().difference(_testStartTime!).inSeconds;
    }

    setState(() {
      _isRunning = false;
      _isHazardWarningActive = false;
      _hazardWarningVisible = false;
    });

    // Flush any OS-buffered bytes and close the file handle before we
    // compute the final trip score or export data.
    await _csvSink?.flush();
    await _csvSink?.close();
    _csvSink = null;

    _calculateSpeedStats();
    _calculateIsoComfort();
    _autoExportMachineData();
  }

  void _calculateSpeedStats() {
    if (_speedHistory.isEmpty) return;
    double sum = 0;
    for (double speed in _speedHistory) {
      sum += speed;
    }
    _averageSpeedKmh = sum / _speedHistory.length;

    double varianceSum = 0;
    for (double speed in _speedHistory) {
      varianceSum += pow(speed - _averageSpeedKmh, 2);
    }
    _speedDeviation = sqrt(varianceSum / _speedHistory.length);
  }

  Future<void> _autoExportMachineData() async {
    if (_validationRows.isEmpty) return;
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
    final double totalTripAv = sqrt(sumSq / _sessionRmsScores.length);

    setState(() {
      _finalRmsAv = totalTripAv;
    });

    final now = DateTime.now();
    double? startLat, startLng, endLat, endLng;
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
      'average_speed': _averageSpeedKmh,
      'speed_deviation': _speedDeviation,
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
          .toList()),
    };

    final int newSessionId = await DatabaseHelper.instance.insertTest(testData);
    for (var anomaly in _sessionAnomalies) {
      anomaly['session_id'] = newSessionId;
      await DatabaseHelper.instance.insertAnomaly(anomaly);
    }
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

      // Phase 3: check proximity to all known hazards on every valid GPS tick.
      _checkHazardProximity(position);

      final newPoint = LatLng(position.latitude, position.longitude);

      double currentSpeed = position.speed * 3.6;
      if (currentSpeed < 0) currentSpeed = 0.0;

      setState(() {
        _currentSpeedKmh = currentSpeed;
        if (currentSpeed > 2.0) {
          _speedHistory.add(currentSpeed);
          _calculateSpeedStats();
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
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsScreen()),
              ).then((_) {
                // Reload defaults in case the user updated them in Settings.
                final prefs = SharedPreferences.getInstance();
                prefs.then((p) {
                  if (!mounted) return;
                  _vehicleInfoController.text =
                      p.getString(kPrefVehicleInfo) ?? _vehicleInfoController.text;
                  _tireInfoController.text =
                      p.getString(kPrefTireInfo) ?? _tireInfoController.text;
                });
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Geçmiş',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
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
                        // _stopTest is async; wrapping avoids VoidCallback mismatch.
                        onTap: _isRunning ? () => _stopTest() : null,
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
                // Phase 3: hazard proximity warning (only visible when active).
                if (_isHazardWarningActive) ...[
                  _buildHazardWarning(),
                  const SizedBox(height: 16),
                ],
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
                                Row(
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
                                    Text(
                                      _formatElapsed(_elapsedSeconds),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.redAccent,
                                          letterSpacing: 1.5),
                                    ),
                                  ],
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
                                gridData: const FlGridData(show: false),
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

  /// Full-width blinking warning banner shown when approaching a known hazard.
  /// Uses [AnimatedOpacity] driven by [_hazardWarningVisible] for a smooth
  /// pulse rather than a hard show/hide flash.
  Widget _buildHazardWarning() {
    return AnimatedOpacity(
      opacity: _hazardWarningVisible ? 1.0 : 0.15,
      duration: const Duration(milliseconds: 400),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.orangeAccent.withOpacity(0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.orangeAccent.withOpacity(0.25),
                blurRadius: 16,
                spreadRadius: 2)
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orangeAccent, size: 30),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BOZUK ZEMİN UYARISI',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Yaklaşık 50 metre ileride kayıtlı bozuk zemin',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '< 50m',
                style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ],
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

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

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
