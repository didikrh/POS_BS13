import 'package:intl/intl.dart';

import '../models/deposit_receipt.dart';
import '../models/store_settings.dart';
import 'escpos_builder.dart';
import 'bluetooth_printer_service.dart';

class DepositReceiptService {
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

  /// Bangun & kirim struk Tanda Terima ke printer yang sedang terhubung.
  /// Mengembalikan true jika berhasil terkirim.
  static Future<bool> printDepositReceipt({
    required DepositReceipt receipt,
    required StoreSettings settings,
  }) async {
    final b = EscPosBuilder(paperWidthMm: settings.paperWidthMm);
    b.reset();

    // ---------------- LOGO RESMI ----------------
    b.align(EscPosAlign.center);
    try {
      b.printLogo();
    } catch (_) {
      // lewati logo, lanjutkan cetak struk seperti biasa.
    }

    // ---------------- HEADER ----------------
    b.align(EscPosAlign.center);
    b.bold(true);
    switch (settings.headerSize) {
      case 0:
        b.textSize(0, 0);
        break;
      case 2:
        b.textSize(1, 1);
        break;
      default:
        b.textSize(0, 1);
    }
    b.line(settings.storeName);
    b.textSize(0, 0);
    b.bold(false);
    b.line(settings.storeAddress);
    b.divider();

    b.align(EscPosAlign.center);
    b.bold(true);
    b.line('TANDA TERIMA');
    b.bold(false);
    b.divider();

    // ---------------- INFO TRANSAKSI ----------------
    b.align(EscPosAlign.left);
    b.line('No. TT  : ${receipt.receiptNo}');
    b.line('Tanggal : ${_dateFmt.format(receipt.receiptDate)}');
    b.line('Petugas : ${receipt.operatorName}');
    b.divider();

    // ---------------- IDENTITAS KASTAMER ----------------
    b.line('Kastamer : ${receipt.clientName}');
    if (receipt.clientContact.trim().isNotEmpty) {
      b.line('Kontak   : ${receipt.clientContact}');
    }
    b.divider();

    // ---------------- DAFTAR BARANG ----------------
    b.bold(true);
    b.line('Barang Disetor/Diserahkan:');
    b.bold(false);
    for (final item in receipt.items) {
      final beratStr = '${_weightStr(item.weight)} ${item.weightUnit}';
      // Nama barang & beratnya digabung jadi SATU baris (nama kiri, berat
      // kanan) supaya lebih mudah dibaca - kalau nama terlalu panjang,
      // twoColumns() otomatis melipat ke baris kedua (berat tetap rata
      // kanan), tidak pernah saling menimpa.
      b.twoColumns(item.itemName, beratStr);
      if (item.notes.trim().isNotEmpty) {
        b.lineWrapped('  Ket: ${item.notes}');
      }
    }
    b.divider();
    b.bold(true);
    b.twoColumns('TOTAL BERAT', '${_weightStr(receipt.totalWeightKg)} kg');
    b.bold(false);

    if (receipt.notes.trim().isNotEmpty) {
      b.divider();
      b.line('Catatan:');
      b.lineWrapped(receipt.notes);
    }
    b.divider();

    // ---------------- FOOTER: QR Code info tanda terima ----------------
    b.align(EscPosAlign.center);
    // Sama seperti struk kasir: QR dibungkus try/catch TERSENDIRI supaya
    // kalau gagal (mis. printer tidak mendukung perintah raster gambar),
    // seluruh Tanda Terima TETAP tercetak tanpa QR-nya saja, bukan batal
    // total.
    try {
      final itemsSummary = receipt.items
          .map((it) => '${it.itemName}:${it.weight}${it.weightUnit}')
          .join(';');
      final qrPayload = 'TT:${receipt.receiptNo}'
          '|TGL:${receipt.receiptDate.toIso8601String()}'
          '|KLIEN:${receipt.clientName}'
          '|PETUGAS:${receipt.operatorName}'
          '|BARANG:$itemsSummary';
      b.qrImage(qrPayload, targetSizeDots: 200);
      b.feed(1);
    } catch (_) {
      // QR gagal dibuat/dirender - lanjutkan tanpa QR.
    }

    b.lineWrapped('Tanda terima ini adalah bukti sah penyetoran/penitipan barang.');
    b.feed(3);
    b.cutPaper();

    final bytes = b.build();
    return BluetoothPrinterService.instance.printBytes(bytes);
  }

  static String _weightStr(double w) {
    if (w == w.roundToDouble()) return w.toStringAsFixed(0);
    return w.toStringAsFixed(2);
  }
}
