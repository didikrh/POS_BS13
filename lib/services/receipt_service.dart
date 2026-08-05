import 'package:intl/intl.dart';

import '../models/pos_transaction.dart';
import '../models/store_settings.dart';
import 'escpos_builder.dart';
import 'bluetooth_printer_service.dart';

class ReceiptService {
  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

  /// Bangun & kirim struk transaksi ke printer yang sedang terhubung.
  /// Mengembalikan true jika berhasil terkirim.
  static Future<bool> printReceipt({
    required PosTransaction trx,
    required StoreSettings settings,
  }) async {
    final b = EscPosBuilder(paperWidthMm: settings.paperWidthMm);
    b.reset();

    // ---------------- HEADER (kustom) ----------------
    b.align(EscPosAlign.center);
    b.bold(true);
    // Ukuran header sekarang ikut Pengaturan (bisa dikustom user), bukan
    // dipaksa 2x tinggi+lebar terus - itu yang bikin nama toko kelihatan
    // "kebesaran" karena lebar tiap huruf ikut digandakan juga, bukan
    // cuma tingginya.
    switch (settings.headerSize) {
      case 0: // Normal
        b.textSize(0, 0);
        break;
      case 2: // Besar (2x tinggi + 2x lebar)
        b.textSize(1, 1);
        break;
      default: // 1 = Sedang (2x tinggi saja, lebar tetap normal)
        b.textSize(0, 1);
    }
    b.line(settings.storeName);
    b.textSize(0, 0);
    b.bold(false);
    b.line(settings.storeAddress);
    b.divider();

    b.align(EscPosAlign.left);
    b.line('No. Struk : ${trx.trxNo}');
    b.line('Tanggal   : ${_dateFmt.format(trx.trxDate)}');
    b.line('Kasir     : ${trx.cashierName}');
    if (trx.customerName.trim().isNotEmpty) {
      b.line('Pelanggan :');
      b.lineWrapped(trx.customerName);
      if (trx.customerAddress.trim().isNotEmpty) {
        b.line('Alamat    :');
        b.lineWrapped(trx.customerAddress);
      }
    }
    b.divider();

    // ---------------- DAFTAR ITEM ----------------
    for (final item in trx.items) {
      b.line(item.productName);
      final qtyPriceStr =
          '${_qtyStr(item.qty)} x ${_currency.format(item.price)}';
      b.twoColumns(qtyPriceStr, _currency.format(item.subtotal));
    }
    b.divider();

    // ---------------- TOTAL ----------------
    b.twoColumns('Subtotal', _currency.format(trx.subtotal));
    if (trx.discount > 0) {
      b.twoColumns('Diskon', '-${_currency.format(trx.discount)}');
    }
    b.bold(true);
    b.twoColumns('TOTAL', _currency.format(trx.total));
    b.bold(false);
    b.twoColumns('Bayar', _currency.format(trx.paid));
    b.twoColumns('Kembali', _currency.format(trx.change));
    b.divider();

    // ---------------- FOOTER: QR Code info transaksi + ucapan ----------------
    b.align(EscPosAlign.center);
    // QR code dibungkus try/catch TERSENDIRI: ini bagian paling kompleks
    // (encoding QR + konversi bitmap ke raster ESC/POS "GS v 0", yang
    // TIDAK didukung sebagian printer thermal murah/generik). Kalau bagian
    // ini gagal, jangan sampai seluruh struk batal tercetak - lewati QR-nya
    // saja, sisa struk (item & total, yang jauh lebih penting) tetap jalan.
    try {
      final qrPayload =
          'TRX:${trx.trxNo}|TGL:${trx.trxDate.toIso8601String()}|TOTAL:${trx.total.toStringAsFixed(0)}|KASIR:${trx.cashierName}';
      b.qrImage(qrPayload, scale: 3);
      b.feed(1);
    } catch (_) {
      // QR gagal dibuat/dirender - lanjutkan tanpa QR.
    }
    b.line(settings.footerGreeting);
    b.feed(3);
    b.cutPaper();

    final bytes = b.build();
    return BluetoothPrinterService.instance.printBytes(bytes);
  }

  static String _qtyStr(double qty) {
    if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
    return qty.toStringAsFixed(2);
  }
}
