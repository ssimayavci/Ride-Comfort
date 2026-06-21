import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('tests_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 9,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      // SQLite disables foreign key enforcement by default. Without this,
      // the ON DELETE CASCADE on road_anomalies.session_id is silently
      // ignored and anomaly rows become orphaned after deleteTest().
      onOpen: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const realNullType = 'REAL';

    await db.execute('''
CREATE TABLE tests (
  id $idType,
  timestamp $textType,
  score $realType,
  latitude $realNullType,
  longitude $realNullType,
  note $textType,
  distance_km $realNullType,
  duration_seconds INTEGER,
  average_speed REAL,    
  speed_deviation REAL,  
  start_lat $realNullType,
  start_lng $realNullType,
  end_lat $realNullType,
  end_lng $realNullType,
  anomaly_count INTEGER DEFAULT 0,
  vehicle_info TEXT,
  tire_info TEXT,
  phone_placement TEXT,
  route_points TEXT,
  ai_report TEXT,
  user_rating INTEGER DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE road_anomalies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER,
  lat REAL,
  lng REAL,
  timestamp TEXT NOT NULL,
  peak_score REAL NOT NULL,
  FOREIGN KEY (session_id) REFERENCES tests (id) ON DELETE CASCADE
)
''');

    // Global hazard registry — persists across all sessions.
    // hit_count lets the UI rank hazards by recurrence severity.
    await db.execute('''
CREATE TABLE global_hazards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  peak_score REAL NOT NULL,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  hit_count INTEGER DEFAULT 1
)
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tests ADD COLUMN distance_km REAL;');
      await db
          .execute('ALTER TABLE tests ADD COLUMN duration_seconds INTEGER;');
      await db.execute('ALTER TABLE tests ADD COLUMN start_lat REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN start_lng REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN end_lat REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN end_lng REAL;');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE tests ADD COLUMN anomaly_count INTEGER DEFAULT 0;');
      await db.execute('''
        CREATE TABLE road_anomalies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER,
          lat REAL,
          lng REAL,
          timestamp TEXT NOT NULL,
          peak_score REAL NOT NULL,
          FOREIGN KEY (session_id) REFERENCES tests (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE tests ADD COLUMN vehicle_info TEXT;');
      await db.execute('ALTER TABLE tests ADD COLUMN tire_info TEXT;');
      await db.execute('ALTER TABLE tests ADD COLUMN phone_placement TEXT;');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tests ADD COLUMN route_points TEXT;');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE tests ADD COLUMN ai_report TEXT;');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE tests ADD COLUMN average_speed REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN speed_deviation REAL;');
    }
    if (oldVersion < 8) {
      // Creates the global hazard registry on devices upgrading from older builds.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS global_hazards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          lat REAL NOT NULL,
          lng REAL NOT NULL,
          peak_score REAL NOT NULL,
          first_seen TEXT NOT NULL,
          last_seen TEXT NOT NULL,
          hit_count INTEGER DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 9) {
      // User's 1-5 star ride comfort rating. DEFAULT 0 means unrated;
      // existing rows are unaffected and never hit a NOT NULL violation.
      await db.execute(
          'ALTER TABLE tests ADD COLUMN user_rating INTEGER DEFAULT 0;');
    }
  }

  Future<int> insertTest(Map<String, dynamic> testItem) async {
    final db = await instance.database;
    return await db.insert('tests', testItem);
  }

  Future<int> insertAnomaly(Map<String, dynamic> anomalyItem) async {
    final db = await instance.database;
    return await db.insert('road_anomalies', anomalyItem);
  }

  Future<int> getTestCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM tests');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> readAllTests() async {
    final db = await instance.database;
    const orderBy = 'timestamp DESC';
    return await db.query('tests', orderBy: orderBy);
  }

  /// For the history list view only. Omits [route_points] (large GPS JSON blob)
  /// and [ai_report] (Markdown text) which are only needed in the detail dialog.
  /// On a history with 50+ sessions this avoids loading several megabytes that
  /// the list view never renders.
  Future<List<Map<String, dynamic>>> readTestSummaries() async {
    final db = await instance.database;
    return await db.query(
      'tests',
      columns: [
        'id',
        'timestamp',
        'score',
        'vehicle_info',
        'tire_info',
        'phone_placement',
        'anomaly_count',
        'distance_km',
        'duration_seconds',
        'average_speed',
        'speed_deviation',
        'start_lat',
        'start_lng',
        'end_lat',
        'end_lng',
        'latitude',
        'longitude',
      ],
      orderBy: 'timestamp DESC',
    );
  }

  /// Returns a single complete test record (all columns) by [id].
  /// Use when opening the detail dialog, or to back up a record before delete
  /// so the undo action can restore every field including route_points.
  Future<Map<String, dynamic>?> readTestById(int id) async {
    final db = await instance.database;
    final rows = await db.query('tests', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Fetches anomalies for multiple sessions in a single SQL round-trip.
  /// Equivalent to calling [readAnomaliesForTest] N times but far more
  /// efficient for bulk export. Returns a Map keyed by session_id.
  Future<Map<int, List<Map<String, dynamic>>>> readAnomaliesForTests(
      List<int> sessionIds) async {
    if (sessionIds.isEmpty) return {};
    final db = await instance.database;
    final String placeholders = List.filled(sessionIds.length, '?').join(',');
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT * FROM road_anomalies '
      'WHERE session_id IN ($placeholders) '
      'ORDER BY session_id, id',
      sessionIds,
    );
    // Group by session_id for O(1) lookup in the export loop.
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final row in rows) {
      final int sid = row['session_id'] as int;
      (grouped[sid] ??= []).add(row);
    }
    return grouped;
  }

  Future<List<Map<String, dynamic>>> readAnomaliesForTest(int sessionId) async {
    final db = await instance.database;
    return await db.query(
      'road_anomalies',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateNote(int id, String newNote) async {
    final db = await instance.database;
    return db.update(
      'tests',
      {'note': newNote},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTest(int id) async {
    final db = await instance.database;
    return await db.delete(
      'tests',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GLOBAL HAZARD REGISTRY
  // ─────────────────────────────────────────────────────────────────────────

  /// Haversine distance in metres between two WGS-84 coordinates.
  /// Pure dart:math — no external package dependency.
  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000.0; // Earth radius in metres
    final double dLat = (lat2 - lat1) * pi / 180.0;
    final double dLng = (lng2 - lng1) * pi / 180.0;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Upserts a road hazard into the global registry.
  ///
  /// If an existing hazard already lies within [mergeRadiusMeters] of the
  /// given coordinates, that record is updated instead of creating a duplicate:
  /// hit_count is incremented, peak_score is raised if the new value is
  /// higher, and last_seen is refreshed. This keeps the table dense with
  /// meaningful clusters rather than scattered per-second duplicates.
  ///
  /// Returns the id of the affected row (inserted or updated).
  Future<int> insertOrUpdateGlobalHazard({
    required double lat,
    required double lng,
    required double peakScore,
    double mergeRadiusMeters = 30.0,
  }) async {
    final db = await instance.database;
    final String now = DateTime.now().toIso8601String();

    // Load only the columns we need for the proximity scan.
    final List<Map<String, dynamic>> existing = await db.query(
      'global_hazards',
      columns: ['id', 'lat', 'lng', 'peak_score', 'hit_count'],
    );

    for (final h in existing) {
      final double dist = _haversineMeters(
        lat, lng, h['lat'] as double, h['lng'] as double,
      );
      if (dist < mergeRadiusMeters) {
        final double newPeak =
            max(peakScore, (h['peak_score'] as num).toDouble());
        await db.update(
          'global_hazards',
          {
            'peak_score': newPeak,
            'last_seen': now,
            'hit_count': (h['hit_count'] as int) + 1,
          },
          where: 'id = ?',
          whereArgs: [h['id']],
        );
        return h['id'] as int;
      }
    }

    // No nearby hazard found — insert a brand-new record.
    return await db.insert('global_hazards', {
      'lat': lat,
      'lng': lng,
      'peak_score': peakScore,
      'first_seen': now,
      'last_seen': now,
      'hit_count': 1,
    });
  }

  /// Returns all global hazards ordered by most-recently seen.
  Future<List<Map<String, dynamic>>> readAllGlobalHazards() async {
    final db = await instance.database;
    return await db.query('global_hazards', orderBy: 'last_seen DESC');
  }

  /// Returns the total count of persisted global hazard records.
  Future<int> getGlobalHazardCount() async {
    final db = await instance.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) FROM global_hazards');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes every row from the global_hazards table.
  /// Used by the Settings screen "Clear Hazard Cache" action.
  Future<void> deleteAllGlobalHazards() async {
    final db = await instance.database;
    await db.delete('global_hazards');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  // AI Raporunu veritabanına kaydetme fonksiyonu
  Future<int> saveAiReport(int id, String report) async {
    final db = await instance.database;
    return await db.update('tests', {'ai_report': report},
        where: 'id = ?', whereArgs: [id]);
  }
}
