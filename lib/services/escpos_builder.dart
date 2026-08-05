import 'dart:convert';
import 'dart:typed_data';

import 'qr_raster.dart';

enum EscPosAlign { left, center, right }

/// Builder ringan untuk perintah ESC/POS mentah (tanpa dependensi tambahan
/// selain apa yang sudah ada di project ini). Ditulis manual supaya penuh
/// kontrol atas byte yang dikirim ke printer 58mm (umumnya lebar cetak
/// efektif 384 dot @ 203dpi untuk kertas 58mm, atau 576 dot untuk 80mm).
class EscPosBuilder {
  final BytesBuilder _buf = BytesBuilder();
  final int paperWidthMm;

  EscPosBuilder({this.paperWidthMm = 58});

  int get dotsPerLine => paperWidthMm >= 80 ? 576 : 384;
  int get charsPerLineNormal => paperWidthMm >= 80 ? 48 : 32;

  void reset() {
    _buf.add([0x1B, 0x40]); // ESC @ : initialize printer
  }

  void align(EscPosAlign a) {
    final n = switch (a) {
      EscPosAlign.left => 0,
      EscPosAlign.center => 1,
      EscPosAlign.right => 2,
    };
    _buf.add([0x1B, 0x61, n]); // ESC a n
  }

  void bold(bool on) {
    _buf.add([0x1B, 0x45, on ? 1 : 0]); // ESC E n
  }

  /// Ukuran teks: 0 = normal, 1 = double height+width, dst (maks 7).
  void textSize(int widthMult, int heightMult) {
    final w = widthMult.clamp(0, 7);
    final h = heightMult.clamp(0, 7);
    final n = (w << 4) | h;
    _buf.add([0x1D, 0x21, n]); // GS ! n
  }

  void underline(bool on) {
    _buf.add([0x1B, 0x2D, on ? 1 : 0]); // ESC - n
  }

  void text(String s) {
    // Printer thermal murah umumnya pakai codepage 1 byte (mis. CP437/
    // WPC1252), bukan UTF-8. Kita encode ke Latin-1 dan buang karakter
    // yang tidak didukung supaya tidak membuat printer macet/hang.
    final safe = _toLatin1Safe(s);
    _buf.add(latin1.encode(safe));
  }

  /// Pecah teks panjang jadi beberapa baris pas lebar kertas TANPA
  /// memenggal di tengah kata. Tanpa ini, printer memotong mentah persis
  /// di batas karakter kertas (mis. "...bukti sa" lalu baris baru "h") -
  /// itu penyebab pemenggalan kata yang aneh di struk.
  List<String> wrapText(String s, {int? width}) {
    final w = width ?? charsPerLineNormal;
    final words = s.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (word.length > w) {
        // Satu kata itu sendiri lebih panjang dari lebar kertas (jarang
        // terjadi) - terpaksa dipotong paksa supaya tidak overflow.
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        var remaining = word;
        while (remaining.length > w) {
          lines.add(remaining.substring(0, w));
          remaining = remaining.substring(w);
        }
        current = remaining;
        continue;
      }
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > w) {
        lines.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  /// Cetak teks panjang yang otomatis dipecah per kata (lihat [wrapText]).
  void lineWrapped(String s, {int? width}) {
    for (final l in wrapText(s, width: width)) {
      line(l);
    }
  }

  void line(String s) {
    text(s);
    newline();
  }

  void newline() {
    _buf.add([0x0A]);
  }

  void feed(int lines) {
    for (var i = 0; i < lines; i++) {
      newline();
    }
  }

  /// Garis pemisah selebar kertas, mis. "--------------------------------"
  void divider({String char = '-'}) {
    line(char * charsPerLineNormal);
  }

  /// Cetak baris 2 kolom rata kiri-kanan (mis. nama barang vs subtotal).
  void twoColumns(String left, String right, {int totalWidth = 0}) {
    final w = totalWidth > 0 ? totalWidth : charsPerLineNormal;
    final space = w - left.length - right.length;
    if (space < 1) {
      line(left);
      line(right.padLeft(w));
    } else {
      line(left + ' ' * space + right);
    }
  }

  void cutPaper({bool partial = true}) {
    _buf.add([0x1D, 0x56, partial ? 1 : 0]); // GS V m
  }

  /// Sisipkan gambar QR Code (dibuat dari teks [data]) sebagai raster image.
  void qrImage(String data, {int scale = 4}) {
    final qr = QrRaster.encode(data);
    final bitmap = qr.toBitmap(scale: scale);
    _buf.add(bitmapToEscPosRaster(bitmap));
    newline();
  }

  /// Sisipkan bitmap barcode 1D yang sudah dirender (lihat BarcodeRaster).
  void barcodeBitmap(List<List<bool>> bitmap) {
    _buf.add(bitmapToEscPosRaster(bitmap));
    newline();
  }

  Uint8List build() => _buf.toBytes();

  String _toLatin1Safe(String input) {
    final buf = StringBuffer();
    for (final rune in input.runes) {
      if (rune <= 0xFF) {
        buf.writeCharCode(rune);
      } else {
        buf.write('?');
      }
    }
    return buf.toString();
  }
}
