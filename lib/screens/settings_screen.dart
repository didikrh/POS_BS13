import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/store_settings.dart';
import '../services/bluetooth_printer_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StoreSettings? _settings;
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _greetCtrl = TextEditingController();
  int _paperWidth = 58;
  int _headerSize = 1;

  List<BluetoothDevice> _pairedDevices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  bool _loadingPrinter = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshPrinterStatus();
  }

  Future<void> _loadSettings() async {
    final s = await DatabaseHelper.instance.getSettings();
    setState(() {
      _settings = s;
      _nameCtrl.text = s.storeName;
      _addrCtrl.text = s.storeAddress;
      _greetCtrl.text = s.footerGreeting;
      _paperWidth = s.paperWidthMm;
      _headerSize = s.headerSize;
    });
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    final updated = _settings!.copyWith(
      storeName: _nameCtrl.text.trim(),
      storeAddress: _addrCtrl.text.trim(),
      footerGreeting: _greetCtrl.text.trim(),
      paperWidthMm: _paperWidth,
      headerSize: _headerSize,
      printerName: _selectedDevice?.name ?? _settings!.printerName,
      printerMac: _selectedDevice?.address ?? _settings!.printerMac,
    );
    await DatabaseHelper.instance.saveSettings(updated);
    setState(() => _settings = updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pengaturan disimpan.')));
  }

  Future<void> _refreshPrinterStatus() async {
    setState(() => _loadingPrinter = true);
    final devices = await BluetoothPrinterService.instance.getPairedDevices();
    final connected = await BluetoothPrinterService.instance.isConnected();
    setState(() {
      _pairedDevices = devices;
      _connected = connected;
      _loadingPrinter = false;
    });
  }

  Future<void> _connectPrinter(BluetoothDevice device) async {
    setState(() => _loadingPrinter = true);
    await BluetoothPrinterService.instance.disconnect();
    final ok = await BluetoothPrinterService.instance.connect(device);
    setState(() {
      _connected = ok;
      _selectedDevice = ok ? device : null;
      _loadingPrinter = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Terhubung ke ${device.name}.'
          : 'Gagal terhubung ke ${device.name}. Pastikan printer menyala & sudah di-pairing di Pengaturan Bluetooth HP.'),
    ));
    if (ok) _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Informasi Toko (Header Struk)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nama Toko', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addrCtrl,
            decoration: const InputDecoration(labelText: 'Alamat Toko', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          Text('Ukuran Nama Toko di Struk',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Kalau nama toko terasa kebesaran/kepotong di struk, coba ganti ke Normal.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          RadioListTile<int>(
            title: const Text('Normal'),
            subtitle: const Text('Ukuran sama seperti teks lain, hanya dicetak tebal.'),
            value: 0,
            groupValue: _headerSize,
            onChanged: (v) => setState(() => _headerSize = v!),
          ),
          RadioListTile<int>(
            title: const Text('Sedang (disarankan)'),
            subtitle: const Text('2x lebih tinggi, lebar tetap normal.'),
            value: 1,
            groupValue: _headerSize,
            onChanged: (v) => setState(() => _headerSize = v!),
          ),
          RadioListTile<int>(
            title: const Text('Besar'),
            subtitle: const Text('2x lebih tinggi DAN 2x lebih lebar (paling mencolok, tapi bisa terlihat kebesaran di kertas 58mm).'),
            value: 2,
            groupValue: _headerSize,
            onChanged: (v) => setState(() => _headerSize = v!),
          ),
          const SizedBox(height: 20),

          Text('Ucapan Footer Struk', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _greetCtrl,
            decoration: const InputDecoration(
                labelText: 'Ucapan Terima Kasih', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),

          Text('Lebar Kertas Printer', style: Theme.of(context).textTheme.titleMedium),
          RadioListTile<int>(
            title: const Text('58 mm'),
            value: 58,
            groupValue: _paperWidth,
            onChanged: (v) => setState(() => _paperWidth = v!),
          ),
          RadioListTile<int>(
            title: const Text('80 mm'),
            value: 80,
            groupValue: _paperWidth,
            onChanged: (v) => setState(() => _paperWidth = v!),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _saveSettings, child: const Text('SIMPAN PENGATURAN')),

          const Divider(height: 40),

          Row(
            children: [
              Expanded(
                child: Text('Printer Thermal Bluetooth',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadingPrinter ? null : _refreshPrinterStatus,
              ),
            ],
          ),
          Row(
            children: [
              Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _connected ? Colors.green : Colors.grey),
              const SizedBox(width: 8),
              Text(_connected ? 'Terhubung' : 'Tidak terhubung'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Pastikan printer sudah di-pairing lewat Pengaturan Bluetooth HP '
            'terlebih dahulu, baru pilih dari daftar di bawah.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_loadingPrinter) const LinearProgressIndicator(),
          if (_pairedDevices.isEmpty && !_loadingPrinter)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada printer ter-pairing.'),
            ),
          ..._pairedDevices.map((d) => ListTile(
                leading: const Icon(Icons.print),
                title: Text(d.name ?? '(tanpa nama)'),
                subtitle: Text(d.address ?? ''),
                trailing: (_settings!.printerMac == d.address && _connected)
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => _connectPrinter(d),
              )),
        ],
      ),
    );
  }
}
