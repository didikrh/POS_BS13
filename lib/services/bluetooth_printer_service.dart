import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Wrapper tipis di atas package `print_bluetooth_thermal` (Bluetooth
/// Classic/SPP - profil yang dipakai mayoritas printer thermal 58mm/80mm
/// murah).
///
/// RIWAYAT: sebelumnya pakai `blue_thermal_printer`, tapi terbukti GAGAL
/// connect di Android 14 (status printer mentok di "Paired", tidak pernah
/// "Connected") - plugin itu sudah lama tidak dirawat pembuatnya dan ada
/// banyak laporan serupa untuk Android 12+. `print_bluetooth_thermal`
/// aktif dirawat, koneksinya dijaga via Kotlin Coroutine di sisi native
/// (lebih tahan lama), dan tidak mewajibkan izin lokasi untuk connect.
///
/// CATATAN PENTING (Android 12+ / API 31+):
/// Tetap butuh izin runtime BLUETOOTH_CONNECT & BLUETOOTH_SCAN (bukan lagi
/// cukup izin lokasi seperti versi Android lama). Sudah ditangani lewat
/// requestPermissions() di bawah, dan wajib dideklarasikan juga di
/// android/app/src/main/AndroidManifest.xml (lihat README) - itu bagian
/// yang TIDAK berubah dari sebelumnya.
class BluetoothPrinterService {
  BluetoothPrinterService._internal();
  static final BluetoothPrinterService instance =
      BluetoothPrinterService._internal();

  Timer? _keepAliveTimer;

  /// KENAPA INI PERLU: banyak printer thermal Bluetooth murah otomatis
  /// memutus koneksi kalau tidak ada aktivitas selama beberapa puluh
  /// detik (mode hemat daya di firmware printer, di luar kendali kode
  /// aplikasi ini). Timer ini hidup di level SINGLETON service (bukan
  /// terikat ke State satu layar tertentu), jadi tetap jalan terus selama
  /// APLIKASI belum ditutup, walau user pindah-pindah tab. Setiap 20
  /// detik, kirim panggilan status ringan ke printer supaya dianggap
  /// "masih aktif". (print_bluetooth_thermal sendiri sudah menjaga koneksi
  /// via Kotlin Coroutine di sisi native, ini lapisan jaga-jaga tambahan.)
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await PrintBluetoothThermal.connectionStatus
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
      } catch (_) {
        // Kalau gagal, biarkan saja - percobaan berikutnya 20 detik lagi.
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location, // fallback untuk Android < 12
    ].request();
    return statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isPermanentlyDenied == false,
    );
  }

  Future<List<BluetoothInfo>> getPairedDevices() async {
    await requestPermissions();
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  /// Cek status koneksi printer. Dicoba beberapa kali dengan jeda singkat
  /// sebelum benar-benar menyerah - supaya tidak salah menampilkan
  /// "printer tidak terhubung" padahal cuma kebetulan lambat merespons.
  Future<bool> isConnected({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final connected = await PrintBluetoothThermal.connectionStatus
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
        if (connected) return true;
      } catch (_) {
        // coba lagi
      }
      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<bool> connect(BluetoothInfo device) async {
    try {
      await requestPermissions();
      final ok = await PrintBluetoothThermal.connect(
          macPrinterAddress: device.macAdress);
      if (ok) _startKeepAlive();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _stopKeepAlive();
    try {
      await PrintBluetoothThermal.disconnect;
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
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }
}
