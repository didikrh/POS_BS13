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

  Future<bool> isConnected() async {
    final connected = await _bt.isConnected;
    return connected ?? false;
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await _bt.connect(device);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
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
      _bt.writeBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
