import 'package:intl/intl.dart';

import '../models/product.dart';
import 'barcode_raster.dart';
import 'escpos_builder.dart';
import 'bluetooth_printer_service.dart';

enum LabelType { barcode1D, qr }

class LabelService {
  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  /// Cetak label identitas barang (nama, harga, kode barcode/QR) ke printer
  /// yang sedang terhubung. [copies] untuk cetak beberapa lembar sekaligus.
  static Future<bool> printProductLabel(
    Product p, {
    LabelType type = LabelType.barcode1D,
    int copies = 1,
    int paperWidthMm = 58,
  }) async {
    final b = EscPosBuilder(paperWidthMm: paperWidthMm);
    b.reset();

    for (var i = 0; i < copies; i++) {
      b.align(EscPosAlign.center);
      b.bold(true);
      b.line(p.name);
      b.bold(false);
      b.line(_currency.format(p.price) + ' / ${p.unit}');
      b.feed(1);

      if (type == LabelType.qr) {
        b.qrImage(p.code, scale: 3);
      } else {
        final bitmap = BarcodeRaster.toBitmap(
          p.code,
          widthPx: b.dotsPerLine - 40,
          heightPx: 80,
        );
        b.barcodeBitmap(bitmap);
      }

      b.line(p.code);
      b.feed(2);
      b.cutPaper();
    }

    final bytes = b.build();
    return BluetoothPrinterService.instance.printBytes(bytes);
  }
}
