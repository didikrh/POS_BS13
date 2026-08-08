import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/store_settings.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/excel_client_service.dart';
import 'cashier_management_screen.dart';

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

  List<BluetoothInfo> _pairedDevices = [];
  BluetoothInfo? _selectedDevice;
  bool _connected = false;
  bool _loadingPrinter = false;
  bool _clientExcelBusy = false;

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
      printerMac: _selectedDevice?.macAdress ?? _settings!.printerMac,
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

  Future<void> _connectPrinter(BluetoothInfo device) async {
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

  Future<void> _exportClientTemplate() async {
    setState(() => _clientExcelBusy = true);
    bool ok = false;
    String? error;
    try {
      ok = await ExcelClientService.exportTemplate();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _clientExcelBusy = false);
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membuat template: $error')));
    } else if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Template Excel berhasil disimpan. Silakan isi lalu import kembali.'),
      ));
    }
  }

  Future<void> _exportClientData() async {
    setState(() => _clientExcelBusy = true);
    bool ok = false;
    String? error;
    try {
      ok = await ExcelClientService.exportData();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _clientExcelBusy = false);
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal export data: $error')));
    } else if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Data kastamer berhasil diexport.')));
    }
  }

  Future<void> _importClientExcel() async {
    setState(() => _clientExcelBusy = true);
    ClientExcelImportResult? result;
    String? error;
    try {
      result = await ExcelClientService.importFromExcel();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _clientExcelBusy = false);
    }

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal import: $error')));
      return;
    }
    if (result == null) return; // user membatalkan pemilihan file

    if (!result.sukses) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Gagal'),
          content: Text(result!.errorFatal!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import Selesai'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✅ ${result!.ditambahkan} kastamer baru ditambahkan.'),
              Text('🔄 ${result.diperbarui} kastamer diperbarui.'),
              if (result.dilewati.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('⚠️ ${result.dilewati.length} baris dilewati:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: result.dilewati.length,
                    itemBuilder: (_, i) {
                      final e = result!.dilewati[i];
                      return Text('  Baris ${e.baris}: ${e.alasan}',
                          style: const TextStyle(fontSize: 12));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
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
          Text('Data Petugas/Kasir', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Ubah nama petugas/kasir supaya tidak selalu tertulis "Kasir Toko" '
            'di struk & Tanda Terima - tiap petugas bisa punya nama sendiri.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CashierManagementScreen()),
            ),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: const Text('Kelola Petugas/Kasir'),
          ),
          const Divider(height: 40),

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
                title: Text(d.name),
                subtitle: Text(d.macAdress),
                trailing: (_settings!.printerMac == d.macAdress && _connected)
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => _connectPrinter(d),
              )),

          const Divider(height: 40),

          Text('Kelola Data Kastamer', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Export/import daftar Kastamer lewat Excel supaya pengisian data '
            'banyak kastamer sekaligus bisa dilakukan dari laptop/komputer.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_clientExcelBusy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _clientExcelBusy ? null : _exportClientTemplate,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Unduh Template'),
              ),
              OutlinedButton.icon(
                onPressed: _clientExcelBusy ? null : _exportClientData,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export Data'),
              ),
              OutlinedButton.icon(
                onPressed: _clientExcelBusy ? null : _importClientExcel,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import dari Excel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
