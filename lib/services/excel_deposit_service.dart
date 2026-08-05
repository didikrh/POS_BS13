import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/deposit_receipt.dart';

/// ============================================================
/// EXPORT / IMPORT TANDA TERIMA VIA EXCEL (.xlsx)
/// ------------------------------------------------------------
/// ATURAN PENTING (disederhanakan supaya tidak rawan bug pengelompokan
/// baris yang rumit): SATU BARIS EXCEL = SATU TANDA TERIMA DENGAN SATU
/// BARANG. Kalau di aplikasi sebuah Tanda Terima berisi beberapa barang,
/// saat di-export akan tampil sebagai beberapa baris terpisah (No. TT,
/// Tanggal, Klien, Petugas-nya sama/berulang). Saat baris-baris itu
/// di-import kembali, masing-masing akan jadi Tanda Terima BARU yang
/// terpisah (satu barang per Tanda Terima) - BUKAN digabung lagi jadi
/// satu Tanda Terima multi-barang seperti aslinya.
///
/// Kolom "No. TT" boleh dikosongkan saat import (nomor baru dibuat
/// otomatis) - hanya berguna untuk referensi ekspor/dokumentasi.
/// ============================================================

const List<String> kDepositExcelHeaders = [
  'No. TT (info saja, kosongkan saat isi baru)',
  'Tanggal (dd/MM/yyyy HH:mm, kosongkan = sekarang)',
  'Nama Klien',
  'Kontak Klien',
  'Petugas',
  'Nama Barang',
  'Berat',
  'Satuan (kg/gram/ton)',
  'Catatan Barang',
];

class DepositExcelImportRowError {
  final int baris;
  final String alasan;
  DepositExcelImportRowError(this.baris, this.alasan);
}

class DepositExcelImportResult {
  final int ditambahkan;
  final List<DepositExcelImportRowError> dilewati;
  final String? errorFatal;

  DepositExcelImportResult({
    this.ditambahkan = 0,
    this.dilewati = const [],
    this.errorFatal,
  });

  bool get sukses => errorFatal == null;
}

class ExcelDepositReceiptService {
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

  static Future<bool> exportTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['TandaTerima'];
    excel.setDefaultSheet('TandaTerima');
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'TandaTerima') excel.delete(name);
    }

    _writeHeader(sheet);
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Contoh: Asmanto Gawage'),
      TextCellValue('0812xxxxxxx'),
      TextCellValue('Kasir Toko'),
      TextCellValue('Kardus'),
      DoubleCellValue(1.5),
      TextCellValue('kg'),
      TextCellValue(''),
    ]);
    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;
    return _saveBytes(Uint8List.fromList(bytes), 'Template_TandaTerima.xlsx');
  }

  /// Export SEMUA Tanda Terima yang ada (1 baris = 1 barang - lihat
  /// catatan aturan di atas file ini).
  static Future<bool> exportData() async {
    // Rentang luas (2 tahun ke belakang sampai besok) supaya praktis
    // "semua data" tanpa perlu UI pilih tanggal terpisah untuk export ini.
    final receipts = await DatabaseHelper.instance.getDepositReceiptsBetween(
      DateTime.now().subtract(const Duration(days: 730)),
      DateTime.now().add(const Duration(days: 1)),
    );

    final excel = Excel.createExcel();
    final sheet = excel['TandaTerima'];
    excel.setDefaultSheet('TandaTerima');
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'TandaTerima') excel.delete(name);
    }
    _writeHeader(sheet);

    for (final r in receipts) {
      final items = await DatabaseHelper.instance.getItemsForDepositReceipt(r.id!);
      for (final item in items) {
        sheet.appendRow([
          TextCellValue(r.receiptNo),
          TextCellValue(_dateFmt.format(r.receiptDate)),
          TextCellValue(r.clientName),
          TextCellValue(r.clientContact),
          TextCellValue(r.operatorName),
          TextCellValue(item.itemName),
          DoubleCellValue(item.weight),
          TextCellValue(item.weightUnit),
          TextCellValue(item.notes),
        ]);
      }
    }
    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;
    final fileName =
        'Data_TandaTerima_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    return _saveBytes(Uint8List.fromList(bytes), fileName);
  }

  static void _writeHeader(Sheet sheet) {
    for (var col = 0; col < kDepositExcelHeaders.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .value = TextCellValue(kDepositExcelHeaders[col]);
    }
  }

  static void _autoFitColumns(Sheet sheet) {
    for (var col = 0; col < kDepositExcelHeaders.length; col++) {
      try {
        sheet.setColumnAutoFit(col);
      } catch (_) {
        // tidak fatal - lanjutkan tanpa auto-fit kalau tidak didukung.
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

  static Future<DepositExcelImportResult?> importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final fileBytes = result.files.single.bytes;
    if (fileBytes == null) {
      return DepositExcelImportResult(
        errorFatal: 'Tidak bisa membaca isi file. Coba pilih ulang file-nya.',
      );
    }

    late final Excel excel;
    try {
      excel = Excel.decodeBytes(fileBytes);
    } catch (e) {
      return DepositExcelImportResult(
        errorFatal: 'File bukan format Excel (.xlsx) yang valid: $e',
      );
    }

    if (excel.tables.isEmpty) {
      return DepositExcelImportResult(errorFatal: 'File Excel tidak berisi sheet apa pun.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    int ditambahkan = 0;
    final dilewati = <DepositExcelImportRowError>[];

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final nomorBarisExcel = rowIndex + 1;

      final tanggalStr = _cellAsString(row, 1)?.trim() ?? '';
      final namaKlien = _cellAsString(row, 2)?.trim() ?? '';
      final kontakKlien = _cellAsString(row, 3)?.trim() ?? '';
      final petugas = _cellAsString(row, 4)?.trim() ?? '';
      final namaBarang = _cellAsString(row, 5)?.trim() ?? '';
      final berat = _cellAsNum(row, 6);
      final satuan = _cellAsString(row, 7)?.trim() ?? '';
      final catatanBarang = _cellAsString(row, 8)?.trim() ?? '';

      final isBlank = namaKlien.isEmpty &&
          namaBarang.isEmpty &&
          (berat == null || berat == 0);
      if (isBlank) continue; // baris kosong - lewati diam-diam

      if (namaKlien.isEmpty) {
        dilewati.add(DepositExcelImportRowError(
            nomorBarisExcel, 'Kolom "Nama Klien" kosong.'));
        continue;
      }
      if (namaBarang.isEmpty) {
        dilewati.add(DepositExcelImportRowError(
            nomorBarisExcel, 'Kolom "Nama Barang" kosong.'));
        continue;
      }
      if (berat == null || berat <= 0) {
        dilewati.add(DepositExcelImportRowError(
            nomorBarisExcel, 'Kolom "Berat" tidak valid (harus angka > 0).'));
        continue;
      }

      try {
        DateTime tanggal;
        if (tanggalStr.isEmpty) {
          tanggal = DateTime.now();
        } else {
          try {
            tanggal = _dateFmt.parse(tanggalStr);
          } catch (_) {
            dilewati.add(DepositExcelImportRowError(nomorBarisExcel,
                'Kolom "Tanggal" formatnya harus dd/MM/yyyy HH:mm (mis. 04/08/2026 15:05).'));
            continue;
          }
        }

        final receiptNo = await DatabaseHelper.instance.nextDepositReceiptNo();
        final receipt = DepositReceipt(
          receiptNo: receiptNo,
          receiptDate: tanggal,
          clientName: namaKlien,
          clientContact: kontakKlien,
          operatorName: petugas.isEmpty ? 'Import Excel' : petugas,
          items: [
            DepositReceiptItem(
              itemName: namaBarang,
              weight: berat,
              weightUnit: (satuan == 'gram' || satuan == 'ton') ? satuan : 'kg',
              notes: catatanBarang,
            ),
          ],
        );
        // saveDepositReceipt SUDAH otomatis: (1) menambah/bikin stok
        // produk terkait, (2) mencatat/update klien - konsisten dengan
        // input manual lewat form, tidak perlu ditangani lagi di sini.
        await DatabaseHelper.instance.saveDepositReceipt(receipt);
        ditambahkan++;
      } catch (e) {
        dilewati.add(DepositExcelImportRowError(nomorBarisExcel, 'Gagal disimpan: $e'));
      }
    }

    return DepositExcelImportResult(ditambahkan: ditambahkan, dilewati: dilewati);
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
        return double.tryParse(value.value.toString().replaceAll(',', '.'));
      default:
        return double.tryParse(value.toString());
    }
  }
}
