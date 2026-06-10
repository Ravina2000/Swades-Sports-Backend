import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'seed.dart';

class AppDatabase {
  AppDatabase({String? path}) {
    _setupNativeLibrary();
    final dbPath = path ?? _defaultPath();
    try {
      _db = sqlite3.open(dbPath);
    } on Object catch (e) {
      stderr.writeln('');
      stderr.writeln('FATAL: could not open SQLite ($e).');
      if (Platform.isWindows) {
        stderr.writeln(
          'On Windows the sqlite3 Dart package needs sqlite3.dll.\n'
          '1. Download "Precompiled Binaries for Windows" (sqlite-dll-win-x64)\n'
          '   from https://www.sqlite.org/download.html\n'
          '2. Put sqlite3.dll inside the backend/ folder (next to pubspec.yaml)\n'
          '3. Run again: dart run bin/server.dart',
        );
      }
      rethrow;
    }
    _configure();
    _migrate();
    seedIfEmpty(_db);
  }

  late final Database _db;

  Database get db => _db;

  /// Resolve the native SQLite library per platform. Windows looks for a bundled
  /// sqlite3.dll; Linux tries versioned Debian paths because libsqlite3-0 only
  /// ships libsqlite3.so.0 while package:sqlite3 opens libsqlite3.so.
  static void _setupNativeLibrary() {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, _openSqliteOnWindows);
    } else if (Platform.isLinux) {
      open.overrideFor(OperatingSystem.linux, _openSqliteOnLinux);
    }
  }

  static DynamicLibrary _openSqliteOnWindows() {
    final candidates = [
      'sqlite3.dll',
      '${Directory.current.path}${Platform.pathSeparator}sqlite3.dll',
    ];
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (_) {}
    }
    return DynamicLibrary.open('sqlite3.dll');
  }

  static DynamicLibrary _openSqliteOnLinux() {
    final dirs = <String>{'/usr/lib', '/lib'};
    for (final arch in ['x86_64', 'aarch64', 'arm64']) {
      dirs.add('/usr/lib/$arch-linux-gnu');
      dirs.add('/lib/$arch-linux-gnu');
    }

    for (final dir in dirs) {
      for (final name in ['libsqlite3.so', 'libsqlite3.so.0']) {
        final path = '$dir${Platform.pathSeparator}$name';
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
    }

    return DynamicLibrary.open('libsqlite3.so');
  }

  static String _defaultPath() {
    final envPath = Platform.environment['DB_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      Directory(File(envPath).parent.path).createSync(recursive: true);
      return envPath;
    }
    return 'quickslot.db';
  }

  void _configure() {
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA foreign_keys = ON;');
    // Wait up to 3s on a locked database instead of failing instantly —
    // relevant when two booking requests hit the same instant.
    _db.execute('PRAGMA busy_timeout = 3000;');
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS venues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        location TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT ''
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS bookings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        venue_id INTEGER NOT NULL,
        slot_date TEXT NOT NULL,
        start_hour INTEGER NOT NULL,
        end_hour INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'confirmed',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (venue_id) REFERENCES venues(id)
      );
    ''');

    _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_active_slot
      ON bookings (venue_id, slot_date, start_hour)
      WHERE status = 'confirmed';
    ''');
  }

  void close() => _db.dispose();
}

bool isSqliteUniqueViolation(Object error) {
  if (error is SqliteException && error.extendedResultCode == 2067) {
    return true;
  }
  final message = error.toString();
  return message.contains('UNIQUE constraint failed') ||
      message.contains('2067');
}
