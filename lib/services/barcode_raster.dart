import 'package:barcode/barcode.dart';

/// Encode teks -> bitmap monokrom barcode 1D (Code128), murni Dart.
/// Dipakai untuk dirender sebagai raster bit-image ESC/POS pada printer
/// thermal (lihat qr_raster.dart -> bitmapToEscPosRaster, dipakai bersama).
class BarcodeRaster {
  /// [widthPx] = lebar total gambar barcode dalam dot printer,
  /// [heightPx] = tinggi batang barcode dalam dot printer.
  static List<List<bool>> toBitmap(
    String data, {
    int widthPx = 300,
    int heightPx = 80,
  }) {
    final bc = Barcode.code128();
    final bitmap =
        List.generate(heightPx, (_) => List.filled(widthPx, false));

    final elements = bc.make(
      data,
      width: widthPx.toDouble(),
      height: heightPx.toDouble(),
      drawText: false,
    );

    for (final element in elements) {
      if (element is BarcodeBar && element.black) {
        final xStart = element.left.round().clamp(0, widthPx - 1);
        final xEnd = (element.left + element.width).round().clamp(0, widthPx);
        for (int y = 0; y < heightPx; y++) {
          for (int x = xStart; x < xEnd; x++) {
            bitmap[y][x] = true;
          }
        }
      }
    }
    return bitmap;
  }
}
