import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../db/database_helper.dart';
import '../models/product.dart';

/// ============================================================
/// EXPORT / IMPORT PRODUK VIA EXCEL (.xlsx)
/// ------------------------------------------------------------
/// Tujuan: supaya pengisian data produk dalam jumlah banyak tidak perlu
/// diketik satu-satu di aplikasi - cukup isi lewat Excel di komputer,
/// lalu import kembali ke database SQLite aplikasi.
///
/// Kolom mengikuti field model Product: Kode | Nama Barang | Harga |
/// Stok | Satuan. Baris pertama = header (WAJIB, jangan dihapus/diubah
/// urutannya saat import).
///
/// Aturan import (upsert berdasarkan Kode):
/// - Kode sudah ada di database  -> data produk tsb DIPERBARUI (update).
/// - Kode belum ada di database  -> produk baru DITAMBAHKAN (insert).
/// - Baris tanpa Kode atau tanpa Nama akan DILEWATI (dicatat di laporan).
/// ============================================================

const List<String> kProductExcelHeaders = [
  'Kode',
  'Nama Barang',
  'Harga',
  'Stok',
  'Satuan',
];

class ExcelImportRowError {
  final int baris; // nomor baris di file Excel (1-based, termasuk header)
  final String alasan;
  ExcelImportRowError(this.baris, this.alasan);
}

class ExcelImportResult {
  final int ditambahkan;
  final int diperbarui;
  final List<ExcelImportRowError> dilewati;
  final String? errorFatal; // diisi kalau file gagal dibuka/parse sama sekali

  ExcelImportResult({
    this.ditambahkan = 0,
    this.diperbarui = 0,
    this.dilewati = const [],
    this.errorFatal,
  });

  int get totalDiproses => ditambahkan + diperbarui;
  bool get sukses => errorFatal == null;
}

class ExcelProductService {
  // ---------------- EXPORT ----------------

  /// Export TEMPLATE kosong (header + 2 baris contoh) - untuk diisi user.
  /// Mengembalikan true kalau berhasil disimpan (atau dibatalkan = false
  /// tanpa error).
  static Future<bool> exportTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Produk'];
    excel.setDefaultSheet('Produk');
    // Hapus sheet bawaan lain kalau ada (Excel.createExcel() kadang bikin
    // 1 sheet default bernama "Sheet1")
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'Produk') excel.delete(name);
    }

    _writeHeader(sheet);

    // Baris contoh - ditandai jelas supaya user tahu harus dihapus/diganti
    sheet.appendRow([
      TextCellValue('CONTOH001'),
      TextCellValue('Contoh: Indomie Goreng'),
      DoubleCellValue(3500),
      DoubleCellValue(100),
      TextCellValue('pcs'),
    ]);
    sheet.appendRow([
      TextCellValue('CONTOH002'),
      TextCellValue('Contoh: Aqua 600ml'),
      DoubleCellValue(4000),
      DoubleCellValue(50),
      TextCellValue('botol'),
    ]);

    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;

    return _saveBytes(Uint8List.fromList(bytes), 'Template_Produk.xlsx');
  }

  /// Export SELURUH DATA produk yang sudah ada di database saat ini.
  static Future<bool> exportData() async {
    final products = await DatabaseHelper.instance.getAllProducts();

    final excel = Excel.createExcel();
    final sheet = excel['Produk'];
    excel.setDefaultSheet('Produk');
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'Produk') excel.delete(name);
    }

    _writeHeader(sheet);

    for (final p in products) {
      sheet.appendRow([
        TextCellValue(p.code),
        TextCellValue(p.name),
        DoubleCellValue(p.price),
        DoubleCellValue(p.stock),
        TextCellValue(p.unit),
      ]);
    }

    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;

    final fileName =
        'Data_Produk_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    return _saveBytes(Uint8List.fromList(bytes), fileName);
  }

  static void _writeHeader(Sheet sheet) {
    for (var col = 0; col < kProductExcelHeaders.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .value = TextCellValue(kProductExcelHeaders[col]);
    }
  }

  static void _autoFitColumns(Sheet sheet) {
    for (var col = 0; col < kProductExcelHeaders.length; col++) {
      try {
        sheet.setColumnAutoFit(col);
      } catch (_) {
        // beberapa versi/plat form mungkin tidak mendukung auto-fit -
        // bukan hal fatal, lanjutkan saja tanpa auto-fit.
      }
    }
  }

  static Future<bool> _saveBytes(Uint8List bytes, String fileName) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan File Excel',
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    return path != null;
  }

  // ---------------- IMPORT ----------------

  /// Buka dialog pilih file, lalu import data produk dari file .xlsx
  /// terpilih. Mengembalikan null kalau user membatalkan pemilihan file
  /// (bukan error).
  static Future<ExcelImportResult?> importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true, // WAJIB true di Android/iOS supaya bytes tidak null
    );
    if (result == null || result.files.isEmpty) return null;

    final fileBytes = result.files.single.bytes;
    if (fileBytes == null) {
      return ExcelImportResult(
        errorFatal:
            'Tidak bisa membaca isi file. Coba pilih ulang file-nya.',
      );
    }

    late final Excel excel;
    try {
      excel = Excel.decodeBytes(fileBytes);
    } catch (e) {
      return ExcelImportResult(
        errorFatal: 'File bukan format Excel (.xlsx) yang valid: $e',
      );
    }

    if (excel.tables.isEmpty) {
      return ExcelImportResult(errorFatal: 'File Excel tidak berisi sheet apa pun.');
    }

    // Ambil sheet PERTAMA yang ditemukan di file - lebih toleran daripada
    // memaksa nama sheet harus persis "Produk" (user mungkin mengubah nama
    // sheet saat mengedit di Excel/Google Sheets).
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    int ditambahkan = 0;
    int diperbarui = 0;
    final dilewati = <ExcelImportRowError>[];

    // Mulai dari baris index 1 (baris ke-2 di Excel) - baris 0 adalah header.
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final nomorBarisExcel = rowIndex + 1; // untuk pesan error (1-based)

      final kode = _cellAsString(row, 0)?.trim() ?? '';
      final nama = _cellAsString(row, 1)?.trim() ?? '';
      final harga = _cellAsNum(row, 2);
      final stok = _cellAsNum(row, 3) ?? 0;
      final satuan = _cellAsString(row, 4)?.trim();

      if (kode.isEmpty && nama.isEmpty) {
        // baris kosong (biasa terjadi di akhir file) - lewati diam-diam,
        // tidak perlu dicatat sebagai error.
        continue;
      }
      if (kode.isEmpty) {
        dilewati.add(ExcelImportRowError(nomorBarisExcel, 'Kolom "Kode" kosong.'));
        continue;
      }
      if (nama.isEmpty) {
        dilewati.add(ExcelImportRowError(nomorBarisExcel, 'Kolom "Nama Barang" kosong.'));
        continue;
      }
      if (harga == null || harga < 0) {
        dilewati.add(ExcelImportRowError(
            nomorBarisExcel, 'Kolom "Harga" tidak valid (harus angka >= 0).'));
        continue;
      }

      try {
        final existing = await DatabaseHelper.instance.getProductByCode(kode);
        if (existing != null) {
          await DatabaseHelper.instance.updateProduct(existing.copyWith(
            name: nama,
            price: harga,
            stock: stok,
            unit: (satuan == null || satuan.isEmpty) ? existing.unit : satuan,
          ));
          diperbarui++;
        } else {
          await DatabaseHelper.instance.insertProduct(Product(
            code: kode,
            name: nama,
            price: harga,
            stock: stok,
            unit: (satuan == null || satuan.isEmpty) ? 'pcs' : satuan,
          ));
          ditambahkan++;
        }
      } catch (e) {
        dilewati.add(ExcelImportRowError(nomorBarisExcel, 'Gagal disimpan: $e'));
      }
    }

    return ExcelImportResult(
      ditambahkan: ditambahkan,
      diperbarui: diperbarui,
      dilewati: dilewati,
    );
  }

  static String? _cellAsString(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final value = row[col]?.value;
    if (value == null) return null;
    return switch (value) {
      TextCellValue() => value.value.toString(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      BoolCellValue() => value.value.toString(),
      _ => value.toString(),
    };
  }

  static double? _cellAsNum(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final value = row[col]?.value;
    if (value == null) return null;
    switch (value) {
      case IntCellValue():
        return value.value.toDouble();
      case DoubleCellValue():
        return value.value;
      case TextCellValue():
        // Jaga-jaga kalau user mengetik angka sebagai teks di Excel
        // (mis. hasil paste dari sumber lain) - tetap coba di-parse.
        return double.tryParse(value.value.toString().replaceAll(',', '.'));
      default:
        return double.tryParse(value.toString());
    }
  }
}
