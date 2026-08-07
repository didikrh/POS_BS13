import 'dart:async';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wrapper tipis di atas package `blue_thermal_printer` (Bluetooth Classic
/// / SPP - profil yang dipakai mayoritas printer thermal 58mm/80mm murah).
///
/// CATATAN PENTING (Android 12+ / API 31+):
/// Butuh izin runtime BLUETOOTH_CONNECT & BLUETOOTH_SCAN (bukan lagi cukup
/// izin lokasi seperti versi Android lama). Sudah ditangani lewat
/// requestPermissions() di bawah, dan wajib dideklarasikan juga di
/// android/app/src/main/AndroidManifest.xml (lihat README).
class BluetoothPrinterService {
  BluetoothPrinterService._internal();
  static final BluetoothPrinterService instance =
      BluetoothPrinterService._internal();

  final BlueThermalPrinter _bt = BlueThermalPrinter.instance;
  Timer? _keepAliveTimer;

  /// KENAPA INI PERLU: banyak printer thermal Bluetooth murah otomatis
  /// memutus koneksi kalau tidak ada aktivitas selama beberapa puluh
  /// detik (mode hemat daya di firmware printer, di luar kendali kode
  /// aplikasi ini). Sebelumnya, aplikasi cuma cek/kirim data ke printer
  /// PAS mau cetak - kalau user pindah-pindah menu tanpa cetak, printer
  /// keburu idle-timeout sendiri, sampai akhirnya harus buka Pengaturan
  /// lagi untuk sambung ulang.
  ///
  /// Timer ini hidup di level SINGLETON service (bukan terikat ke State
  /// satu layar tertentu), jadi tetap jalan terus selama APLIKASI belum
  /// ditutup, walau user pindah-pindah tab. Setiap 20 detik, kirim
  /// panggilan status ringan ke printer supaya dianggap "masih aktif".
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await _bt.isConnected.timeout(const Duration(seconds: 4), onTimeout: () => null);
      } catch (_) {
        // Kalau gagal, biarkan saja - percobaan berikutnya 20 detik lagi.
        // Status sebenarnya akan tetap dicek ulang (dengan retry) di
        // isConnected()/printBytes() saat user benar-benar mau cetak.
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location, // fallback untuk Android < 12
    ].request();
    return statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isPermanentlyDenied == false,
    );
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    await requestPermissions();
    try {
      return await _bt.getBondedDevices();
    } catch (_) {
      return [];
    }
  }

  /// Cek status koneksi printer. Plugin `blue_thermal_printer` ini dikenal
  /// KADANG memberi hasil yang tidak konsisten kalau dipanggil segera
  /// setelah pindah layar (native method channel-nya perlu sedikit waktu
  /// untuk "settle"). Daripada langsung menyimpulkan "tidak terhubung"
  /// dari SATU kali panggilan yang mungkin kebetulan gagal/lambat, di
  /// sini dicoba beberapa kali dengan jeda singkat sebelum benar-benar
  /// menyerah - supaya tidak salah menampilkan "printer tidak terhubung"
  /// padahal sebenarnya masih terhubung.
  Future<bool> isConnected({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final connected = await _bt.isConnected.timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );
        if (connected == true) return true;
      } catch (_) {
        // coba lagi
      }
      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await _bt.connect(device);
      _startKeepAlive();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _stopKeepAlive();
    try {
      await _bt.disconnect();
    } catch (_) {
      // abaikan - printer mungkin memang sudah terputus
    }
  }

  /// Kirim byte mentah (hasil dari EscPosBuilder.build()) ke printer yang
  /// sedang terhubung.
  Future<bool> printBytes(Uint8List bytes) async {
    try {
      final connected = await isConnected();
      if (!connected) return false;
      await _bt.writeBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
