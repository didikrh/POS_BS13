import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/cashier.dart';
import '../models/store_settings.dart';
import '../models/pos_transaction.dart';
import '../models/transaction_item.dart';

/// ============================================================
/// DATABASE HELPER (SQLite via sqflite)
/// ------------------------------------------------------------
/// Kenapa SQLite dipilih sebagai "paling ringan & tidak boros memori":
/// - SQLite adalah bagian dari OS Android/iOS itu sendiri (native library),
///   sehingga TIDAK menambah ukuran APK dengan database engine terpisah,
///   dan tidak menjalankan proses server terpisah (embedded, in-process).
/// - Cocok untuk data transaksi POS yang butuh relasi (transaksi -> item)
///   dan agregasi laporan (SUM, GROUP BY per tanggal/kasir) yang sulit
///   dilakukan efisien pada penyimpanan key-value murni (mis. Hive/
///   SharedPreferences).
/// - Alternatif LEBIH ringan untuk kasus sederhana (tanpa relasi/join):
///   Hive atau sembast (NoSQL murni Dart). Namun untuk kebutuhan laporan
///   transaksi POS yang relasional, SQLite tetap pilihan paling efisien
///   secara keseluruhan (bukan hanya soal ukuran, tapi juga kecepatan
///   query laporan).
/// ============================================================
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pos_thermal.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs'
      );
    ''');

    await db.execute('''
      CREATE TABLE cashiers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        pin TEXT NOT NULL,
        name TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE store_settings (
        id INTEGER PRIMARY KEY,
        store_name TEXT NOT NULL,
        store_address TEXT NOT NULL,
        footer_greeting TEXT NOT NULL,
        printer_name TEXT,
        printer_mac TEXT,
        paper_width_mm INTEGER NOT NULL DEFAULT 58
      );
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trx_no TEXT UNIQUE NOT NULL,
        trx_date TEXT NOT NULL,
        cashier_name TEXT NOT NULL,
        customer_name TEXT,
        customer_address TEXT,
        subtotal REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        paid REAL NOT NULL,
        change REAL NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        price REAL NOT NULL,
        qty REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id)
      );
    ''');

    // Index untuk mempercepat laporan berdasar tanggal (query ringan & cepat)
    await db.execute(
        'CREATE INDEX idx_trx_date ON transactions (trx_date);');
    await db.execute(
        'CREATE INDEX idx_trxitem_trxid ON transaction_items (transaction_id);');

    // Data awal: 1 baris pengaturan toko default + 1 kasir default
    await db.insert('store_settings', StoreSettings().toMap());
    await db.insert('cashiers',
        Cashier(username: 'kasir1', pin: '1234', name: 'Kasir Toko').toMap());
  }

  // ---------------- PRODUCTS ----------------

  Future<int> insertProduct(Product p) async {
    final db = await database;
    return db.insert('products', p.toMap()..remove('id'));
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
    return db.update('products', p.toMap(),
        where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Product>> getAllProducts({String? search}) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: search != null && search.isNotEmpty
          ? 'name LIKE ? OR code LIKE ?'
          : null,
      whereArgs: search != null && search.isNotEmpty
          ? ['%$search%', '%$search%']
          : null,
      orderBy: 'name ASC',
    );
    return rows.map((e) => Product.fromMap(e)).toList();
  }

  Future<Product?> getProductByCode(String code) async {
    final db = await database;
    final rows =
        await db.query('products', where: 'code = ?', whereArgs: [code]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  // ---------------- CASHIERS ----------------

  Future<Cashier?> loginCashier(String username, String pin) async {
    final db = await database;
    final rows = await db.query('cashiers',
        where: 'username = ? AND pin = ?', whereArgs: [username, pin]);
    if (rows.isEmpty) return null;
    return Cashier.fromMap(rows.first);
  }

  Future<List<Cashier>> getAllCashiers() async {
    final db = await database;
    final rows = await db.query('cashiers', orderBy: 'name ASC');
    return rows.map((e) => Cashier.fromMap(e)).toList();
  }

  Future<int> insertCashier(Cashier c) async {
    final db = await database;
    return db.insert('cashiers', c.toMap()..remove('id'));
  }

  // ---------------- STORE SETTINGS ----------------

  Future<StoreSettings> getSettings() async {
    final db = await database;
    final rows = await db.query('store_settings', where: 'id = 1');
    if (rows.isEmpty) {
      final s = StoreSettings();
      await db.insert('store_settings', s.toMap());
      return s;
    }
    return StoreSettings.fromMap(rows.first);
  }

  Future<void> saveSettings(StoreSettings s) async {
    final db = await database;
    await db.update('store_settings', s.toMap(),
        where: 'id = ?', whereArgs: [s.id]);
  }

  // ---------------- TRANSACTIONS ----------------

  /// Simpan transaksi + item sekaligus dalam SATU transaction DB (atomik),
  /// dan kurangi stok produk terkait.
  Future<int> saveTransaction(PosTransaction trx) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final trxId = await txn.insert('transactions', trx.toMap()..remove('id'));

      for (final item in trx.items) {
        await txn.insert(
          'transaction_items',
          item.toMap()
            ..remove('id')
            ..['transaction_id'] = trxId,
        );

        if (item.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [item.qty, item.productId],
          );
        }
      }
      return trxId;
    });
  }

  Future<List<PosTransaction>> getTransactionsBetween(
      DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'trx_date BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'trx_date DESC',
    );
    return rows.map((e) => PosTransaction.fromMap(e)).toList();
  }

  Future<List<TransactionItem>> getItemsForTransaction(int trxId) async {
    final db = await database;
    final rows = await db.query('transaction_items',
        where: 'transaction_id = ?', whereArgs: [trxId]);
    return rows.map((e) => TransactionItem.fromMap(e)).toList();
  }

  Future<String> nextTrxNo() async {
    final now = DateTime.now();
    final db = await database;
    final countToday = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM transactions WHERE trx_date LIKE ?",
      ['${now.toIso8601String().substring(0, 10)}%'],
    ));
    final seq = (countToday ?? 0) + 1;
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'TRX$ymd-${seq.toString().padLeft(4, '0')}';
  }
}
