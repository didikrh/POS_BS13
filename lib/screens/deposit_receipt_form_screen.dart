import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/client.dart';
import '../models/deposit_receipt.dart';
import '../services/deposit_receipt_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../state/app_state.dart';

const List<String> kWeightUnits = ['kg', 'gram', 'ton'];

/// Status pengecekan apakah nama barang yang diketik sudah ada di Master
/// Produk atau belum - dipakai untuk menampilkan/menyembunyikan field
/// Kode Barang secara otomatis.
enum _ProductMatchStatus { checking, existing, newProduct, empty }

class _DraftItem {
  final nameCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String unit = 'kg';
  _ProductMatchStatus matchStatus = _ProductMatchStatus.empty;
  Timer? _debounce;

  void dispose() {
    _debounce?.cancel();
    nameCtrl.dispose();
    weightCtrl.dispose();
    notesCtrl.dispose();
    codeCtrl.dispose();
  }
}

class DepositReceiptFormScreen extends StatefulWidget {
  const DepositReceiptFormScreen({super.key});

  @override
  State<DepositReceiptFormScreen> createState() => _DepositReceiptFormScreenState();
}

class _DepositReceiptFormScreenState extends State<DepositReceiptFormScreen> {
  final _clientNameCtrl = TextEditingController();
  final _clientContactCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_DraftItem> _items = [_DraftItem()];
  bool _processing = false;

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _clientContactCtrl.dispose();
    _notesCtrl.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  void _addItemRow() {
    setState(() => _items.add(_DraftItem()));
  }

  void _removeItemRow(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  /// Dipanggil tiap kali nama barang di suatu baris berubah. Dicek (dengan
  /// jeda singkat supaya tidak query ke DB di setiap ketikan huruf) apakah
  /// nama itu sudah ada di Master Produk - kalau BELUM ADA, field Kode
  /// Barang otomatis muncul supaya barang baru ini bisa terhubung dengan
  /// benar ke tabel produk saat stoknya otomatis ditambahkan nanti.
  void _onItemNameChanged(_DraftItem draft) {
    draft._debounce?.cancel();
    final name = draft.nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => draft.matchStatus = _ProductMatchStatus.empty);
      return;
    }
    setState(() => draft.matchStatus = _ProductMatchStatus.checking);
    draft._debounce = Timer(const Duration(milliseconds: 500), () async {
      final product = await DatabaseHelper.instance.getProductByName(name);
      if (!mounted) return;
      // Nama boleh saja sudah berubah lagi selagi menunggu - cek ulang
      // supaya tidak menampilkan status untuk nama yang sudah usang.
      if (draft.nameCtrl.text.trim() != name) return;
      setState(() {
        draft.matchStatus = product != null
            ? _ProductMatchStatus.existing
            : _ProductMatchStatus.newProduct;
      });
    });
  }

  Future<void> _submit() async {
    final clientName = _clientNameCtrl.text.trim();
    if (clientName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Kastamer wajib diisi.')),
      );
      return;
    }

    // Validasi baris barang: nama & berat wajib diisi, berat harus angka > 0.
    final parsedItems = <DepositReceiptItem>[];
    for (var i = 0; i < _items.length; i++) {
      final draft = _items[i];
      final name = draft.nameCtrl.text.trim();
      final weightStr = draft.weightCtrl.text.trim();
      if (name.isEmpty && weightStr.isEmpty) continue; // baris kosong - lewati
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Baris ${i + 1}: Nama Barang wajib diisi.')),
        );
        return;
      }
      final weight = double.tryParse(weightStr.replaceAll(',', '.'));
      if (weight == null || weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Baris ${i + 1}: Berat harus berupa angka lebih dari 0.')),
        );
        return;
      }
      parsedItems.add(DepositReceiptItem(
        itemName: name,
        weight: weight,
        weightUnit: draft.unit,
        notes: draft.notesCtrl.text.trim(),
        productCode: draft.matchStatus == _ProductMatchStatus.newProduct
            ? draft.codeCtrl.text.trim()
            : null,
      ));
    }

    if (parsedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal isi 1 baris barang.')),
      );
      return;
    }

    setState(() => _processing = true);

    // Pola yang SAMA seperti Checkout Kasir: seluruh proses dibungkus
    // try/catch/finally supaya tombol TIDAK PERNAH macet berputar diam
    // walau ada kegagalan (DB, printer, dsb) - ini pelajaran mahal dari
    // bug yang sama persis di fitur kasir sebelumnya.
    late final DepositReceipt receipt;
    bool printed = false;
    bool connected = false;
    String? errorMessage;
    String? printErrorDetail;

    try {
      final appState = context.read<AppState>();
      final receiptNo = await DatabaseHelper.instance.nextDepositReceiptNo();
      receipt = DepositReceipt(
        receiptNo: receiptNo,
        receiptDate: DateTime.now(),
        clientName: clientName,
        clientContact: _clientContactCtrl.text.trim(),
        operatorName: appState.activeCashier?.name ?? '-',
        notes: _notesCtrl.text.trim(),
        items: parsedItems,
      );

      await DatabaseHelper.instance.saveDepositReceipt(receipt);

      final settings = await DatabaseHelper.instance.getSettings();

      try {
        connected = await BluetoothPrinterService.instance
            .isConnected()
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      } catch (_) {
        connected = false;
      }

      if (connected) {
        try {
          printed = await DepositReceiptService.printDepositReceipt(
                  receipt: receipt, settings: settings)
              .timeout(const Duration(seconds: 10), onTimeout: () => false);
        } catch (e) {
          printed = false;
          printErrorDetail = e.toString();
        }
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) setState(() => _processing = false);
    }

    if (!mounted) return;

    if (errorMessage != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tanda Terima Gagal Disimpan'),
          content: Text(
            'Terjadi kesalahan saat menyimpan:\n$errorMessage\n\n'
            'Data belum tersimpan. Silakan coba lagi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(printed
            ? 'Tanda Terima Berhasil'
            : connected
                ? 'Tersimpan (Cetak Gagal)'
                : 'Tersimpan (Printer Belum Terhubung)'),
        content: Text(
          printed
              ? 'Tanda Terima "${receipt.receiptNo}" berhasil dicetak.'
              : connected
                  ? 'Data sudah tersimpan, namun gagal dicetak.'
                      '${printErrorDetail != null ? '\n\nDetail: $printErrorDetail' : ''}'
                      '\n\nBisa cetak ulang dari daftar Tanda Terima.'
                  : 'Data sudah tersimpan, namun printer belum terhubung. '
                      'Sambungkan printer di menu Pengaturan lalu cetak ulang dari daftar Tanda Terima.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // tutup dialog
              Navigator.of(context).pop(true); // kembali, beri tahu perlu refresh
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tanda Terima Baru')),
      body: AbsorbPointer(
        absorbing: _processing,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Identitas Kastamer', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // Autocomplete dari daftar Klien tersimpan (sama dengan yang
            // dipakai transaksi kasir) - pilih klien lama supaya kontak
            // otomatis terisi, atau ketik nama baru (otomatis tercatat
            // sebagai klien baru saat Tanda Terima disimpan).
            Autocomplete<Client>(
              displayStringForOption: (c) => c.name,
              optionsBuilder: (value) async {
                if (value.text.trim().isEmpty) return const Iterable<Client>.empty();
                return DatabaseHelper.instance.getAllClients(search: value.text.trim());
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (v) => _clientNameCtrl.text = v,
                  decoration: const InputDecoration(
                      labelText: 'Nama Kastamer *', border: OutlineInputBorder()),
                );
              },
              onSelected: (client) {
                _clientNameCtrl.text = client.name;
                if (client.contact.isNotEmpty) _clientContactCtrl.text = client.contact;
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _clientContactCtrl,
              decoration: const InputDecoration(
                  labelText: 'No. HP / Alamat (opsional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('Barang Diterima',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Baris'),
                ),
              ],
            ),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Barang #${index + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeItemRow(index),
                            ),
                        ],
                      ),
                      TextField(
                        controller: draft.nameCtrl,
                        onChanged: (_) => _onItemNameChanged(draft),
                        decoration: InputDecoration(
                          labelText: 'Nama Barang',
                          border: const OutlineInputBorder(),
                          helperText: switch (draft.matchStatus) {
                            _ProductMatchStatus.checking => 'Memeriksa Master Produk...',
                            _ProductMatchStatus.existing =>
                              '✓ Sudah ada di Master Produk - stok akan otomatis ditambah.',
                            _ProductMatchStatus.newProduct =>
                              'Barang baru - belum ada di Master Produk.',
                            _ProductMatchStatus.empty => null,
                          },
                          helperStyle: TextStyle(
                            color: draft.matchStatus == _ProductMatchStatus.newProduct
                                ? Colors.orange[800]
                                : Colors.green[700],
                          ),
                        ),
                      ),
                      // Field Kode Barang HANYA muncul kalau nama barang yang
                      // diketik belum ada di Master Produk - supaya barang
                      // baru ini bisa terhubung dengan kode yang benar saat
                      // otomatis ditambahkan sebagai produk baru nanti.
                      // Boleh dikosongkan (kode akan dibuat otomatis).
                      if (draft.matchStatus == _ProductMatchStatus.newProduct) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: draft.codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kode Barang (opsional, produk baru)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.qr_code, size: 20),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: draft.weightCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*[.,]?\d{0,2}$')),
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'Berat', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: draft.unit,
                              decoration:
                                  const InputDecoration(border: OutlineInputBorder()),
                              items: kWeightUnits
                                  .map((u) =>
                                      DropdownMenuItem(value: u, child: Text(u)))
                                  .toList(),
                              onChanged: (v) => setState(() => draft.unit = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: draft.notesCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Keterangan (opsional)',
                            border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Catatan Umum (opsional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _processing ? null : _submit,
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.print),
              label: Text(_processing ? 'MEMPROSES...' : 'SIMPAN & CETAK TANDA TERIMA'),
            ),
          ],
        ),
      ),
    );
  }
}
