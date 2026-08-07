import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/cashier.dart';
import '../models/store_settings.dart';
import '../models/pos_transaction.dart';
import '../models/transaction_item.dart';
import '../models/deposit_receipt.dart';
import '../models/client.dart';

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
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// PENTING: HP yang sudah pernah install versi aplikasi sebelumnya TIDAK
  /// BOLEH kehilangan data yang sudah tersimpan - jadi di sini cuma
  /// menambah kolom/tabel BARU, BUKAN drop & recreate tabel yang sudah ada.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE store_settings ADD COLUMN header_size INTEGER NOT NULL DEFAULT 1;",
      );
    }
    if (oldVersion < 3) {
      await _createDepositReceiptTables(db);
    }
    if (oldVersion < 4) {
      await _createClientsTable(db);
    }
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
        paper_width_mm INTEGER NOT NULL DEFAULT 58,
        header_size INTEGER NOT NULL DEFAULT 1
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

    await _createDepositReceiptTables(db);
    await _createClientsTable(db);
  }

  /// Tabel Klien/Pelanggan/Nasabah BERSAMA - dipakai baik transaksi kasir
  /// maupun Tanda Terima. `name COLLATE NOCASE UNIQUE` supaya "Budi" dan
  /// "budi" dianggap klien yang SAMA (tidak dobel), dan supaya lookup
  /// auto-tambah-jika-belum-ada bisa dilakukan lewat INSERT OR IGNORE.
  Future<void> _createClientsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        contact TEXT,
        address TEXT,
        UNIQUE (name COLLATE NOCASE)
      );
    ''');
  }

  /// Tabel untuk fitur "Tanda Terima" (transaksi NON-KASIR: klien setor/
  /// titip barang). Sengaja terpisah total dari tabel `transactions` milik
  /// kasir - beda struktur data & tujuan sama sekali.
  Future<void> _createDepositReceiptTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deposit_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_no TEXT UNIQUE NOT NULL,
        receipt_date TEXT NOT NULL,
        client_name TEXT NOT NULL,
        client_contact TEXT,
        operator_name TEXT NOT NULL,
        notes TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS deposit_receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        weight REAL NOT NULL,
        weight_unit TEXT NOT NULL DEFAULT 'kg',
        notes TEXT,
        FOREIGN KEY (receipt_id) REFERENCES deposit_receipts (id)
      );
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_deposit_date ON deposit_receipts (receipt_date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_deposititem_receiptid ON deposit_receipt_items (receipt_id);');
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

  /// Cari produk berdasarkan NAMA (case-insensitive) - dipakai untuk
  /// mencocokkan barang setoran Tanda Terima dengan produk yang sudah ada
  /// di Master Produk, supaya stoknya nambah ke produk yang SAMA alih-alih
  /// bikin produk duplikat tiap kali klien setor barang yang sama.
  Future<Product?> getProductByName(String name) async {
    final db = await database;
    final rows = await db.query('products',
        where: 'name = ? COLLATE NOCASE', whereArgs: [name]);
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

  Future<void> updateCashier(Cashier c) async {
    final db = await database;
    await db.update('cashiers', c.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [c.id]);
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
          // Diambil dulu nilainya, dihitung & DIBULATKAN ke 2 digit desimal
          // di Dart, baru ditulis balik - bukan pakai "SET stock = stock -
          // ?" langsung di SQL. Kalau qty desimal dipakai berulang kali
          // (mis. transaksi kg berturut-turut), pengurangan float murni
          // bisa menumpuk sisa presisi aneh (mis. 2.9999999999999996)
          // walau nilainya seharusnya bulat 2 digit saja.
          final rows = await txn
              .query('products', where: 'id = ?', whereArgs: [item.productId]);
          if (rows.isNotEmpty) {
            final currentStock = (rows.first['stock'] as num).toDouble();
            await txn.update(
              'products',
              {'stock': _round2(currentStock - item.qty)},
              where: 'id = ?',
              whereArgs: [item.productId],
            );
          }
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

  // ---------------- TANDA TERIMA (deposit/titip barang, non-kasir) ----------------

  /// Simpan Tanda Terima + item barangnya sekaligus dalam SATU transaction
  /// DB (atomik) - sama seperti saveTransaction() untuk kasir. TIDAK
  /// mengurangi stok produk (barang titipan bukan barang dagangan toko).
  /// Simpan Tanda Terima + item barangnya sekaligus dalam SATU transaction
  /// DB (atomik) - sama seperti saveTransaction() untuk kasir.
  ///
  /// SETIAP barang yang disetor OTOMATIS masuk/ditambahkan ke stok Master
  /// Produk supaya bisa langsung dijual (sesuai permintaan): kalau sudah
  /// ada produk dengan NAMA yang sama (case-insensitive), stoknya
  /// ditambah sebesar berat setoran (dikonversi ke satuan produk yang
  /// sudah ada); kalau belum ada, dibuatkan produk baru otomatis dengan
  /// harga jual 0 (SENGAJA 0 - aplikasi tidak tahu harga jual yang benar,
  /// harus diisi manual oleh staf di Master Produk sebelum dijual).
  Future<int> saveDepositReceipt(DepositReceipt receipt) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final receiptId =
          await txn.insert('deposit_receipts', receipt.toMap()..remove('id'));

      for (var i = 0; i < receipt.items.length; i++) {
        final item = receipt.items[i];
        await txn.insert(
          'deposit_receipt_items',
          item.toMap()
            ..remove('id')
            ..['receipt_id'] = receiptId,
        );
        await _upsertProductStockFromDeposit(txn, item, i);
      }

      // Klien juga otomatis tercatat/ter-update di daftar Klien bersama.
      await _upsertClient(txn,
          name: receipt.clientName, contact: receipt.clientContact);

      return receiptId;
    });
  }

  /// Tambahkan berat barang setoran ke stok produk yang sudah ada (kalau
  /// namanya cocok), atau buat produk baru otomatis kalau belum ada sama
  /// sekali. Berat dikonversi ke satuan produk yang SUDAH ADA supaya
  /// penjumlahan stoknya benar walau satuan di form Tanda Terima beda
  /// (mis. setoran dalam gram, produk sudah tercatat dalam kg).
  Future<void> _upsertProductStockFromDeposit(
      DatabaseExecutor txn, DepositReceiptItem item, int itemIndex) async {
    final rows = await txn.query('products',
        where: 'name = ? COLLATE NOCASE', whereArgs: [item.itemName]);

    if (rows.isEmpty) {
      // Kalau user mengisi Kode Barang secara manual (field itu cuma
      // muncul di form saat nama barangnya BELUM ADA di Master Produk),
      // pakai kode itu supaya produk baru ini benar-benar terhubung ke
      // kode yang diinginkan staf. Kalau dikosongkan, tetap dibuatkan
      // otomatis dari nama+waktu+indeks supaya tidak wajib diisi.
      final manualCode = item.productCode?.trim();
      final autoCode = (manualCode != null && manualCode.isNotEmpty)
          ? manualCode
          : 'TTP-${DateTime.now().millisecondsSinceEpoch}-$itemIndex';
      await txn.insert(
        'products',
        Product(
          code: autoCode,
          name: item.itemName,
          price: 0,
          stock: _round2(item.weight),
          unit: item.weightUnit,
        ).toMap()
          ..remove('id'),
      );
      return;
    }

    final existing = Product.fromMap(rows.first);
    final convertedWeight =
        _convertWeight(item.weight, item.weightUnit, existing.unit);
    await txn.update(
      'products',
      {'stock': _round2(existing.stock + convertedWeight)},
      where: 'id = ?',
      whereArgs: [existing.id],
    );
  }

  /// Bulatkan ke maksimal 2 digit desimal. Dipakai SETIAP KALI stok produk
  /// ditulis (baik dikurangi saat jual-beli maupun ditambah saat setoran
  /// kastamer), supaya nilai stok yang terakumulasi dari banyak transaksi
  /// desimal tidak menumpuk presisi berlebih akibat pembulatan floating-
  /// point (mis. 1.2000000000000002).
  double _round2(double value) => (value * 100).round() / 100;

  /// Konversi berat antar satuan kg/gram/ton. Kalau satuan tujuan bukan
  /// salah satu dari ketiganya (mis. produk lama satuannya "pcs"), berat
  /// ditambahkan APA ADANYA tanpa konversi - lebih baik daripada memaksa
  /// konversi yang tidak masuk akal secara satuan.
  double _convertWeight(double value, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) return value;
    const toKg = {'kg': 1.0, 'gram': 0.001, 'ton': 1000.0};
    if (!toKg.containsKey(fromUnit) || !toKg.containsKey(toUnit)) return value;
    final valueInKg = value * toKg[fromUnit]!;
    return valueInKg / toKg[toUnit]!;
  }

  Future<List<DepositReceipt>> getDepositReceiptsBetween(
      DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'deposit_receipts',
      where: 'receipt_date BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'receipt_date DESC',
    );
    return rows.map((e) => DepositReceipt.fromMap(e)).toList();
  }

  Future<List<DepositReceiptItem>> getItemsForDepositReceipt(
      int receiptId) async {
    final db = await database;
    final rows = await db.query('deposit_receipt_items',
        where: 'receipt_id = ?', whereArgs: [receiptId]);
    return rows.map((e) => DepositReceiptItem.fromMap(e)).toList();
  }

  Future<String> nextDepositReceiptNo() async {
    final now = DateTime.now();
    final db = await database;
    final countToday = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM deposit_receipts WHERE receipt_date LIKE ?",
      ['${now.toIso8601String().substring(0, 10)}%'],
    ));
    final seq = (countToday ?? 0) + 1;
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'TT$ymd-${seq.toString().padLeft(4, '0')}';
  }

  // ---------------- CLIENTS (klien/pelanggan/nasabah bersama) ----------------

  /// Cari-atau-buat klien berdasarkan nama (case-insensitive). Menerima
  /// DatabaseExecutor (bukan Database) supaya bisa dipanggil DI DALAM
  /// transaction (Tanda Terima) MAUPUN standalone (transaksi kasir).
  Future<int> _upsertClient(DatabaseExecutor txn,
      {required String name, String contact = '', String address = ''}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return -1; // tidak ada nama - tidak dicatat

    final rows = await txn.query('clients',
        where: 'name = ? COLLATE NOCASE', whereArgs: [trimmedName]);

    if (rows.isEmpty) {
      return txn.insert('clients', {
        'name': trimmedName,
        'contact': contact,
        'address': address,
      });
    }

    final existing = rows.first;
    final existingId = existing['id'] as int;
    // Lengkapi kontak/alamat yang masih kosong - JANGAN timpa data yang
    // sudah pernah diisi sebelumnya.
    final updates = <String, dynamic>{};
    final currentContact = (existing['contact'] as String?) ?? '';
    final currentAddress = (existing['address'] as String?) ?? '';
    if (currentContact.isEmpty && contact.trim().isNotEmpty) {
      updates['contact'] = contact.trim();
    }
    if (currentAddress.isEmpty && address.trim().isNotEmpty) {
      updates['address'] = address.trim();
    }
    if (updates.isNotEmpty) {
      await txn.update('clients', updates, where: 'id = ?', whereArgs: [existingId]);
    }
    return existingId;
  }

  /// Versi PUBLIC dari _upsertClient - dipanggil dari luar (mis. saat
  /// transaksi kasir selesai disimpan) untuk auto-tambah klien baru.
  Future<int> upsertClientGetId(
      {required String name, String contact = '', String address = ''}) async {
    final db = await database;
    return _upsertClient(db, name: name, contact: contact, address: address);
  }

  Future<List<Client>> getAllClients({String? search}) async {
    final db = await database;
    final rows = await db.query(
      'clients',
      where: search != null && search.isNotEmpty ? 'name LIKE ?' : null,
      whereArgs: search != null && search.isNotEmpty ? ['%$search%'] : null,
      orderBy: 'name ASC',
    );
    return rows.map((e) => Client.fromMap(e)).toList();
  }

  Future<Client?> getClientByName(String name) async {
    final db = await database;
    final rows = await db
        .query('clients', where: 'name = ? COLLATE NOCASE', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  /// Simpan klien dari Excel import - berbeda dari [upsertClientGetId]:
  /// yang ini MENIMPA kontak/alamat dengan data baru dari file (karena
  /// import Excel memang alat untuk EDIT MASSAL yang disengaja user),
  /// bukan sekadar melengkapi data yang masih kosong.
  Future<int> saveClientFromImport(
      {required String name, String contact = '', String address = ''}) async {
    final db = await database;
    final trimmedName = name.trim();
    final existing = await getClientByName(trimmedName);
    if (existing != null) {
      await db.update(
        'clients',
        {'contact': contact, 'address': address},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.id!;
    }
    return db.insert('clients', {
      'name': trimmedName,
      'contact': contact,
      'address': address,
    });
  }
}
