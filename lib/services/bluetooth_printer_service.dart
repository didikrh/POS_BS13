import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Info printer yang sudah ter-pairing di HP (nama + alamat MAC).
class BtDevice {
  final String name;
  final String mac;
  BtDevice({required this.name, required this.mac});
}

/// Wrapper di atas CHANNEL NATIVE CUSTOM ("custom_spp_bluetooth" - lihat
/// CustomSppPlugin.kt yang disisipkan otomatis oleh tool/patch_android.py).
///
/// RIWAYAT: sebelumnya coba dua plugin pub.dev berturut-turut
/// (blue_thermal_printer, lalu print_bluetooth_thermal) - KEDUANYA gagal
/// connect ke sebagian printer generik murah di Android 12-14 (status
/// mentok "Paired", RFCOMM socket standar selalu ditolak printer).
/// Terbukti aplikasi "Serial Bluetooth Terminal" berhasil connect ke
/// printer yang SAMA di HP yang SAMA - artinya OS/hardware tidak
/// bermasalah, masalahnya di CARA plugin membuka socket RFCOMM-nya.
///
/// Solusinya: kode koneksi native sendiri (CustomSppPlugin.kt) dengan 3
/// lapis percobaan - socket secure standar, lalu insecure, lalu fallback
/// reflection ke channel RFCOMM 1 langsung - persis pola yang dipakai
/// aplikasi "serial terminal" yang terbukti berhasil.
class BluetoothPrinterService {
  BluetoothPrinterService._internal();
  static final BluetoothPrinterService instance =
      BluetoothPrinterService._internal();

  static const MethodChannel _channel = MethodChannel('custom_spp_bluetooth');

  Timer? _keepAliveTimer;
  String? _connectedMac;

  /// KENAPA INI PERLU: banyak printer thermal Bluetooth murah otomatis
  /// memutus koneksi kalau tidak ada aktivitas selama beberapa puluh detik
  /// (mode hemat daya di firmware printer). Timer ini hidup di level
  /// SINGLETON service (bukan terikat ke satu layar), jadi tetap jalan
  /// terus selama aplikasi belum ditutup, walau user pindah-pindah tab.
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await _channel
            .invokeMethod<bool>('isConnected')
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

  Future<List<BtDevice>> getPairedDevices() async {
    await requestPermissions();
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
      if (result == null) return [];
      return result
          .map((e) => Map<Object?, Object?>.from(e as Map))
          .map((m) => BtDevice(
                name: (m['name'] as String?) ?? '(tanpa nama)',
                mac: (m['mac'] as String?) ?? '',
              ))
          .where((d) => d.mac.isNotEmpty)
          .toList();
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
        final connected = await _channel
            .invokeMethod<bool>('isConnected')
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
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

  Future<bool> connect(BtDevice device) async {
    try {
      await requestPermissions();
      // Percobaan koneksi (3 lapis di sisi native) bisa makan waktu lebih
      // lama dari panggilan biasa - beri jeda cukup panjang.
      final ok = await _channel
          .invokeMethod<bool>('connect', {'mac': device.mac})
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (ok == true) {
        _connectedMac = device.mac;
        _startKeepAlive();
      }
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _stopKeepAlive();
    _connectedMac = null;
    try {
      await _channel.invokeMethod<void>('disconnect');
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
      final ok = await _channel.invokeMethod<bool>('writeBytes', {'bytes': bytes});
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
