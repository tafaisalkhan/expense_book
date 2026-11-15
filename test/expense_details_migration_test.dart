import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/core/database/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('version 5 expenses gain optional details without losing rows',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(inMemoryDatabasePath);
    try {
      await db.execute(
          'CREATE TABLE expenses (id INTEGER PRIMARY KEY, amount REAL)');
      await db.insert('expenses', {'id': 1, 'amount': 1200.0});
      await DatabaseMigrations.onUpgrade(db, 5, 6);
      final rows = await db.query('expenses');
      expect(rows.single['amount'], 1200.0);
      expect(rows.single['detailsJson'], '{}');
    } finally {
      await db.close();
    }
  });
}
