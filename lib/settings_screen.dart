import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences keys — exported so iso_comfort_screen can read them.
// ─────────────────────────────────────────────────────────────────────────────
const String kPrefVehicleInfo = 'default_vehicle_info';
const String kPrefTireInfo = 'default_tire_info';

// ─────────────────────────────────────────────────────────────────────────────
// Privacy policy text
// ─────────────────────────────────────────────────────────────────────────────

const String _privacyTr = '''
Son güncelleme: Mayıs 2025

Ride Comfort uygulaması ("Uygulama"), sürüş konforu analizine yönelik olarak geliştirilen bağımsız bir mobil ölçüm aracıdır. Bu Gizlilik Politikası, Uygulamanın hangi verileri topladığını, bu verilerin nasıl kullanıldığını ve korunduğunu açıklamaktadır.

1. Toplanan Veriler
Uygulama yalnızca şu verileri toplar:
  • İvmeölçer (accelerometer) verileri: Titreşim analizi için ham sensör okumalarını işler.
  • GPS konum verileri: Güzergah haritalama ve anomali coğrafi etiketlemesi için kullanılır. Konum verisi yalnızca test aktif olduğu sürece okunur.
  • Araç ve lastik bilgisi: Yalnızca kullanıcı tarafından manuel olarak girilir ve analiz raporlarına dahil edilir.

2. Verilerin Saklanması
Tüm veriler yalnızca cihazınızda yerel olarak saklanır (SQLite veritabanı ve geçici CSV dosyaları). Hiçbir kişisel veri harici bir sunucuya aktarılmaz.

3. Yapay Zeka Analiz Özelliği
"YZ Raporu Oluştur" özelliği kullanıldığında, oturum istatistikleri (skor, mesafe, anomali sayısı, araç bilgisi) anonim olarak Google Gemini API'sine gönderilir. Konum koordinatları bu isteğe dahil edilmez. Google'ın gizlilik politikası geçerlidir.

4. Üçüncü Taraflarla Paylaşım
Verileriniz hiçbir üçüncü tarafla pazarlama, reklamcılık veya analitik amaçlarla paylaşılmaz veya satılmaz.

5. Veri Silme
Tüm test geçmişinizi Geçmiş ekranından, tüm bozuk zemin noktalarını Ayarlar ekranındaki "Tehlike Önbelleğini Temizle" seçeneğiyle silebilirsiniz. Uygulamayı kaldırmak tüm yerel verileri kalıcı olarak siler.

6. İletişim
Gizlilikle ilgili sorularınız için: simayavci2022@gmail.com
''';

const String _privacyEn = '''
Last updated: May 2025

Ride Comfort ("the App") is an independent mobile measurement tool designed for ride comfort analysis. This Privacy Policy describes what data the App collects, how it is used, and how it is protected.

1. Data Collected
The App collects only the following data:
  • Accelerometer data: Raw sensor readings processed for vibration analysis.
  • GPS location data: Used for route mapping and anomaly geo-tagging. Location is read only while a test is actively running.
  • Vehicle and tyre information: Entered manually by the user and included in analysis reports only.

2. Data Storage
All data is stored locally on your device only (SQLite database and temporary CSV files). No personal data is transmitted to any external server.

3. AI Analysis Feature
When the "Generate AI Report" feature is used, session statistics (score, distance, anomaly count, vehicle info) are sent anonymously to the Google Gemini API. Location coordinates are not included in this request. Google's privacy policy applies to that transmission.

4. Sharing with Third Parties
Your data is never shared with or sold to any third party for marketing, advertising, or analytics purposes.

5. Data Deletion
You can delete all test history from the History screen, and clear all road hazard data from Settings → "Clear Hazard Cache". Uninstalling the App permanently deletes all local data.

6. Contact
For privacy-related questions: simayavci2022@gmail.com
''';

// ─────────────────────────────────────────────────────────────────────────────
// Settings Screen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _tireController = TextEditingController();

  bool _isSaved = false;
  int _hazardCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _tireController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final count = await DatabaseHelper.instance.getGlobalHazardCount();
    if (!mounted) return;
    setState(() {
      _vehicleController.text = prefs.getString(kPrefVehicleInfo) ?? '';
      _tireController.text = prefs.getString(kPrefTireInfo) ?? '';
      _hazardCount = count;
    });
  }

  Future<void> _saveDefaults() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefVehicleInfo, _vehicleController.text.trim());
    await prefs.setString(kPrefTireInfo, _tireController.text.trim());
    if (!mounted) return;
    setState(() => _isSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isSaved = false);
    });
  }

  Future<void> _clearHazardCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: _GlassCard(
          borderGlow: Colors.redAccent.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.delete_sweep_outlined,
                    color: Colors.redAccent, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'ÖNBELLEĞI TEMİZLE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tüm kayıtlı bozuk zemin noktaları silinecek. Bu işlem geri alınamaz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.blueGrey, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('İPTAL'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.15),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                                color: Colors.redAccent.withOpacity(0.5)),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('SİL',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      await DatabaseHelper.instance.deleteAllGlobalHazards();
      if (!mounted) return;
      setState(() => _hazardCount = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tüm bozuk zemin verileri silindi.'),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _GlassCard(
          borderGlow: Colors.blueAccent.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row
                Row(
                  children: [
                    const Icon(Icons.privacy_tip_outlined,
                        color: Colors.blueAccent, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'GİZLİLİK POLİTİKASI',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.5),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close,
                          color: Colors.blueGrey, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.blueGrey.withOpacity(0.4), height: 1),
                const SizedBox(height: 4),
                // Scrollable body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _policySection('🇹🇷  Türkçe', _privacyTr),
                        const SizedBox(height: 20),
                        Divider(
                            color: Colors.blueGrey.withOpacity(0.3), height: 1),
                        const SizedBox(height: 20),
                        _policySection('🇬🇧  English', _privacyEn),
                        const SizedBox(height: 8),
                      ],
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

  Widget _policySection(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Text(body,
            style: const TextStyle(
                color: Colors.blueGrey, fontSize: 11.5, height: 1.65)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('AYARLAR',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Section: Default Parameters ───────────────────────────
                _sectionLabel(
                    Icons.tune_outlined, 'VARSAYILAN TEST PARAMETRELERİ'),
                const SizedBox(height: 12),
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Her test başlatıldığında otomatik doldurulur.',
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 11,
                              height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        _fieldLabel('Varsayılan Araç Bilgisi'),
                        const SizedBox(height: 6),
                        _inputField(
                          controller: _vehicleController,
                          hint: 'Örn: Renault Megane 4',
                          icon: Icons.directions_car_outlined,
                        ),
                        const SizedBox(height: 14),
                        _fieldLabel('Varsayılan Lastik Bilgisi'),
                        const SizedBox(height: 6),
                        _inputField(
                          controller: _tireController,
                          hint: 'Örn: 205/55 R16 Yaz Lastiği',
                          icon: Icons.trip_origin_outlined,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: Icon(
                              _isSaved
                                  ? Icons.check_circle_outline
                                  : Icons.save_outlined,
                              size: 18),
                          label: Text(
                            _isSaved
                                ? 'KAYDEDİLDİ!'
                                : 'VARSAYILAN OLARAK KAYDET',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isSaved
                                ? Colors.greenAccent.withOpacity(0.15)
                                : Colors.blueAccent.withOpacity(0.12),
                            foregroundColor: _isSaved
                                ? Colors.greenAccent
                                : Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: (_isSaved
                                          ? Colors.greenAccent
                                          : Colors.blueAccent)
                                      .withOpacity(0.4)),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _saveDefaults,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Section: Data Management ──────────────────────────────
                _sectionLabel(Icons.storage_outlined, 'VERİ YÖNETİMİ'),
                const SizedBox(height: 12),
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color:
                                        Colors.orangeAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Colors.orangeAccent, size: 14),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$_hazardCount nokta',
                                    style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Kayıtlı bozuk zemin noktası',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Bu veriler gelecekteki sürüşlerde sesli uyarı vermek için kullanılır.',
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 11,
                              height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon:
                              const Icon(Icons.delete_sweep_outlined, size: 16),
                          label: const Text(
                            'TEHLİKE ÖNBELLEĞİNİ TEMİZLE',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(
                                color: Colors.redAccent.withOpacity(0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed:
                              _hazardCount > 0 ? _clearHazardCache : null,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Section: Siri Integration (Sadeleştirilmiş) ────────────
                _sectionLabel(Icons.mic_none, 'SESLİ KOMUTLAR'),
                const SizedBox(height: 12),
                _GlassCard(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.record_voice_over,
                          color: Colors.greenAccent, size: 20),
                    ),
                    title: const Text("Sesli Komutlar Etkin",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        "Sadece 'Hey Siri, Ride Comfort testi başlat' veya 'Hey Siri, Ride Comfort testi bitir' demen yeterli.",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 11)),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Section: Legal ────────────────────────────────────────
                _sectionLabel(Icons.gavel_outlined, 'YASAL'),
                const SizedBox(height: 12),
                _GlassCard(
                  child: InkWell(
                    onTap: _showPrivacyPolicy,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.blueAccent.withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.privacy_tip_outlined,
                                color: Colors.blueAccent, size: 18),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Gizlilik Politikası',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                SizedBox(height: 2),
                                Text('Privacy Policy',
                                    style: TextStyle(
                                        color: Colors.blueGrey, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.blueGrey, size: 13),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // ── App version footer ────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Ride Comfort',
                        style: TextStyle(
                            color: Colors.blueGrey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v1.0.0  •  ISO 2631-1 Compliant',
                        style: TextStyle(
                            color: Colors.blueGrey.shade700, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build helpers ─────────────────────────────────────────────────────────

  Widget _sectionLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 13),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
              color: Colors.blueGrey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold));
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.blueGrey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GlassCard — local copy matching the one in iso_comfort_screen.dart.
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
