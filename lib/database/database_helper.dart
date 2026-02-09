import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('morfin_auth.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_name TEXT,
      left_little TEXT, left_ring TEXT, left_middle TEXT, left_index TEXT, left_thumb TEXT,
      right_thumb TEXT, right_index TEXT, right_middle TEXT, right_ring TEXT, right_little TEXT
    )
    ''');
  }

  // Used for Home Screen Counter
  Future<int> getUserCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Used for Enrollment
  Future<int> addUser(String name, Map<String, dynamic> fingers) async {
    final db = await instance.database;
    Map<String, dynamic> row = {'user_name': name};
    row.addAll(fingers);
    return await db.insert('users', row);
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await instance.database;
    return await db.query('users');
  }

  // lightweight fetch (getAllUsersLite)
  Future<List<Map<String, dynamic>>> getAllUsersLite() async {
    final db = await instance.database;

    // Instead of query('users'), we specify ONLY the columns we need
    return await db.query(
        'users',
        columns: ['id', 'user_name'] // This ignores all the fingerprint columns!
    );
  }

  Future<int> deleteUser(int id) async {
    final db = await instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearDatabase() async {
    final db = await instance.database;
    await db.delete('users');
  }

  Future<int> updateUserName(int id, String newName) async {
    final db = await instance.database;
    return await db.update('users', {'user_name': newName}, where: 'id = ?', whereArgs: [id]);
  }
}