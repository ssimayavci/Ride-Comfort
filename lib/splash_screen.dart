import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'iso_comfort_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // Fire-and-forget: clean up stale CSV files in the background.
    // Runs concurrently with the 3-second splash delay so it costs nothing.
    _cleanOldCsvFiles();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const IsoComfortScreen()),
        );
      }
    });
  }

  /// Deletes `machine_data_*.csv` files from the system temporary directory
  /// that are older than 7 days. Each completed test produces one such file;
  /// without cleanup they accumulate indefinitely and inflate the app's
  /// on-device storage footprint — a common App Store review red flag.
  Future<void> _cleanOldCsvFiles() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final DateTime cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final FileSystemEntity entity in tempDir.list()) {
        if (entity is File) {
          final String name = entity.uri.pathSegments.last;
          if (name.startsWith('machine_data_') && name.endsWith('.csv')) {
            final FileStat stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      // GC is best-effort; a failure here must never interrupt the splash flow.
      debugPrint('CSV GC error: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/app_icon.png',
              width: 140,
              height: 140,
              errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.speed, size: 120, color: Colors.greenAccent),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: _pulseAnimation,
              child: const Text(
                'RIDE COMFORT',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.greenAccent,
                  letterSpacing: 4.0,
                  shadows: [
                    Shadow(color: Colors.greenAccent, blurRadius: 10),
                  ]
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
