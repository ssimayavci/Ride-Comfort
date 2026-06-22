import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'azure_api_service.dart';

// ── GLOBAL DATA LIST ────────────────────────────────────────────────────────
// Lists crowdsourced comfort test results fetched from Azure. Each row shows
// the RMS score, the user's star rating, and a globe icon that opens a small
// bounded FlutterMap pinned to that test's location.
class GlobalDataScreen extends StatefulWidget {
  const GlobalDataScreen({super.key});

  @override
  State<GlobalDataScreen> createState() => _GlobalDataScreenState();
}

class _GlobalDataScreenState extends State<GlobalDataScreen> {
  late Future<List<Map<String, dynamic>>> _locationsFuture;

  @override
  void initState() {
    super.initState();
    _locationsFuture = AzureApiService.fetchGlobalLocations();
  }

  void _showLocationMapDialog(Map<String, dynamic> location) {
    final double lat = (location['lat'] as num?)?.toDouble() ?? 0;
    final double lng = (location['lng'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.blueGrey.withOpacity(0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Test Konumu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(lat, lng),
                        initialZoom: 14,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.emir.konforolcer',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_pin,
                                color: Colors.redAccent,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Veriler',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFF020617),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _locationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.lightBlueAccent),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Veriler yüklenirken hata oluştu.',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final locations = snapshot.data ?? [];

          // ── Table header row ───────────────────────────────────────────
          // Same flex ratios (2 / 3 / 1) and horizontal padding as the list
          // item Row below, so the labels line up exactly with their columns.
          const headerStyle = TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
            fontSize: 12,
          );
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: Text('Konfor Değeri', style: headerStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Puan',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Rota',
                    textAlign: TextAlign.right,
                    style: headerStyle,
                  ),
                ),
              ],
            ),
          );

          if (locations.isEmpty) {
            return Column(
              children: [
                header,
                const Expanded(
                  child: Center(
                    child: Text(
                      'Henüz global veri bulunmuyor.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              header,
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: locations.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final location = locations[index];
                    final double rmsScore =
                        (location['rms_score'] as num?)?.toDouble() ?? 0;
                    final int userRating =
                        (location['user_rating'] as num?)?.toInt() ?? 0;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.blueGrey.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          // ── Column 1: RMS Score ─────────────────────
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${rmsScore.toStringAsFixed(2)} m/s²',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // ── Column 2: User rating (stars) ───────────
                          Expanded(
                            flex: 3,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                final star = i + 1;
                                return Icon(
                                  userRating >= star
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: userRating >= star
                                      ? const Color(0xFFFFD700)
                                      : Colors.blueGrey,
                                  size: 18,
                                );
                              }),
                            ),
                          ),
                          // ── Column 3: Globe icon → map dialog ───────
                          Expanded(
                            flex: 1,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                icon: const Icon(Icons.public,
                                    color: Colors.lightBlueAccent),
                                onPressed: () =>
                                    _showLocationMapDialog(location),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
