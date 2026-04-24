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
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
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
  start_lat $realNullType,
  start_lng $realNullType,
  end_lat $realNullType,
  end_lng $realNullType,
  anomaly_count INTEGER DEFAULT 0,
  vehicle_info TEXT,
  tire_info TEXT,
  phone_placement TEXT,
  route_points TEXT,
  ai_report TEXT
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
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tests ADD COLUMN distance_km REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN duration_seconds INTEGER;');
      await db.execute('ALTER TABLE tests ADD COLUMN start_lat REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN start_lng REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN end_lat REAL;');
      await db.execute('ALTER TABLE tests ADD COLUMN end_lng REAL;');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE tests ADD COLUMN anomaly_count INTEGER DEFAULT 0;');
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
