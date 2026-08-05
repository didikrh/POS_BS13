import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../db/database_helper.dart';

/// ============================================================
/// EXPORT / IMPORT KLIEN VIA EXCEL (.xlsx)
/// ------------------------------------------------------------
/// Kolom: Nama | Kontak | Alamat. Baris pertama = header.
///
/// Aturan import (upsert berdasarkan Nama, case-insensitive - SAMA
/// dengan aturan auto-tambah klien saat transaksi kasir/Tanda Terima):
/// - Nama sudah ada  -> kontak/alamat klien tsb DIPERBARUI.
/// - Nama belum ada  -> klien baru DITAMBAHKAN.
/// - Baris tanpa Nama akan DILEWATI (dicatat di laporan).
/// ============================================================

const List<String> kClientExcelHeaders = ['Nama', 'Kontak', 'Alamat'];

class ClientExcelImportRowError {
  final int baris;
  final String alasan;
  ClientExcelImportRowError(this.baris, this.alasan);
}

class ClientExcelImportResult {
  final int ditambahkan;
  final int diperbarui;
  final List<ClientExcelImportRowError> dilewati;
  final String? errorFatal;

  ClientExcelImportResult({
    this.ditambahkan = 0,
    this.diperbarui = 0,
    this.dilewati = const [],
    this.errorFatal,
  });

  int get totalDiproses => ditambahkan + diperbarui;
  bool get sukses => errorFatal == null;
}

class ExcelClientService {
  static Future<bool> exportTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Klien'];
    excel.setDefaultSheet('Klien');
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'Klien') excel.delete(name);
    }

    _writeHeader(sheet);
    sheet.appendRow([
      TextCellValue('Contoh: Budi Santoso'),
      TextCellValue('0812xxxxxxx'),
      TextCellValue('Jl. Contoh No. 1'),
    ]);
    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;
    return _saveBytes(Uint8List.fromList(bytes), 'Template_Klien.xlsx');
  }

  static Future<bool> exportData() async {
    final clients = await DatabaseHelper.instance.getAllClients();

    final excel = Excel.createExcel();
    final sheet = excel['Klien'];
    excel.setDefaultSheet('Klien');
    for (final name in List<String>.from(excel.tables.keys)) {
      if (name != 'Klien') excel.delete(name);
    }

    _writeHeader(sheet);
    for (final c in clients) {
      sheet.appendRow([
        TextCellValue(c.name),
        TextCellValue(c.contact),
        TextCellValue(c.address),
      ]);
    }
    _autoFitColumns(sheet);

    final bytes = excel.save();
    if (bytes == null) return false;
    final fileName =
        'Data_Klien_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    return _saveBytes(Uint8List.fromList(bytes), fileName);
  }

  static void _writeHeader(Sheet sheet) {
    for (var col = 0; col < kClientExcelHeaders.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .value = TextCellValue(kClientExcelHeaders[col]);
    }
  }

  static void _autoFitColumns(Sheet sheet) {
    for (var col = 0; col < kClientExcelHeaders.length; col++) {
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

  static Future<ClientExcelImportResult?> importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final fileBytes = result.files.single.bytes;
    if (fileBytes == null) {
      return ClientExcelImportResult(
        errorFatal: 'Tidak bisa membaca isi file. Coba pilih ulang file-nya.',
      );
    }

    late final Excel excel;
    try {
      excel = Excel.decodeBytes(fileBytes);
    } catch (e) {
      return ClientExcelImportResult(
        errorFatal: 'File bukan format Excel (.xlsx) yang valid: $e',
      );
    }

    if (excel.tables.isEmpty) {
      return ClientExcelImportResult(errorFatal: 'File Excel tidak berisi sheet apa pun.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    int ditambahkan = 0;
    int diperbarui = 0;
    final dilewati = <ClientExcelImportRowError>[];

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final nomorBarisExcel = rowIndex + 1;

      final nama = _cellAsString(row, 0)?.trim() ?? '';
      final kontak = _cellAsString(row, 1)?.trim() ?? '';
      final alamat = _cellAsString(row, 2)?.trim() ?? '';

      if (nama.isEmpty && kontak.isEmpty && alamat.isEmpty) continue; // baris kosong
      if (nama.isEmpty) {
        dilewati.add(ClientExcelImportRowError(nomorBarisExcel, 'Kolom "Nama" kosong.'));
        continue;
      }

      try {
        final existing = await DatabaseHelper.instance.getClientByName(nama);
        await DatabaseHelper.instance.saveClientFromImport(
          name: nama,
          contact: kontak,
          address: alamat,
        );
        if (existing != null) {
          diperbarui++;
        } else {
          ditambahkan++;
        }
      } catch (e) {
        dilewati.add(ClientExcelImportRowError(nomorBarisExcel, 'Gagal disimpan: $e'));
      }
    }

    return ClientExcelImportResult(
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
}
