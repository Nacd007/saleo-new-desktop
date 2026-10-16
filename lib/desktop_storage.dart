import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> configureEncryptedDesktopDatabase(
  Database db,
  String password,
) async {
  try {
    final cipher = await db.rawQuery('PRAGMA cipher');
    if (cipher.isEmpty) throw StateError('Encryption library unavailable');
    await db.execute("PRAGMA cipher = 'sqlcipher'");
    await db.execute('PRAGMA legacy = 4');
    await db.execute("PRAGMA key = '${password.replaceAll("'", "''")}'");
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
    await db.execute('PRAGMA foreign_keys = ON');
  } catch (_) {
    // Never put SQL containing the encryption key into a UI error or log.
    throw StateError(
      'The encrypted company cache could not be unlocked. No data was deleted.',
    );
  }
}
