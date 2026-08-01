import 'dart:typed_data';
import 'package:qr/qr.dart';

/// Encode teks -> matrix modul QR Code (murni Dart, tanpa dibutuhkan
/// widget/UI). Dipakai untuk dirender sebagai raster bit-image ESC/POS
/// pada printer thermal (lihat escpos_builder.dart -> rasterFromMatrix).
class QrRaster {
  final int moduleCount;
  final bool Function(int row, int col) isDark;

  QrRaster._(this.moduleCount, this.isDark);

  factory QrRaster.encode(String data) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    return QrRaster._(qrImage.moduleCount, qrImage.isDark);
  }

  /// Bangun bitmap monokrom (List<List<bool>>) dengan "quiet zone" (margin
  /// putih) di sekelilingnya, dan setiap modul diperbesar [scale] dot.
  List<List<bool>> toBitmap({int scale = 4, int quietZoneModules = 2}) {
    final n = moduleCount + quietZoneModules * 2;
    final size = n * scale;
    final bitmap = List.generate(size, (_) => List.filled(size, false));

    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        if (isDark(r, c)) {
          final py0 = (r + quietZoneModules) * scale;
          final px0 = (c + quietZoneModules) * scale;
          for (int dy = 0; dy < scale; dy++) {
            for (int dx = 0; dx < scale; dx++) {
              bitmap[py0 + dy][px0 + dx] = true;
            }
          }
        }
      }
    }
    return bitmap;
  }
}

/// Konversi bitmap monokrom (List<List<bool>>, true = titik hitam) menjadi
/// perintah RASTER BIT IMAGE ESC/POS: "GS v 0" -> siap dikirim ke printer.
Uint8List bitmapToEscPosRaster(List<List<bool>> bitmap) {
  final height = bitmap.length;
  final width = height == 0 ? 0 : bitmap[0].length;
  final widthBytes = (width + 7) ~/ 8;

  final data = <int>[];
  data.addAll([0x1D, 0x76, 0x30, 0x00]); // GS v 0 m(=0 normal)
  data.add(widthBytes & 0xFF);
  data.add((widthBytes >> 8) & 0xFF);
  data.add(height & 0xFF);
  data.add((height >> 8) & 0xFF);

  for (int y = 0; y < height; y++) {
    for (int xb = 0; xb < widthBytes; xb++) {
      int byteVal = 0;
      for (int bit = 0; bit < 8; bit++) {
        final x = xb * 8 + bit;
        final isBlack = x < width && bitmap[y][x];
        if (isBlack) {
          byteVal |= (0x80 >> bit);
        }
      }
      data.add(byteVal);
    }
  }
  return Uint8List.fromList(data);
}
