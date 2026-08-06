import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/pos_transaction.dart';
import '../models/client.dart';
import '../models/store_settings.dart';
import '../services/receipt_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../state/app_state.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _custNameCtrl = TextEditingController();
  final _custAddrCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  bool _processing = false;
  bool _retryingPrint = false;

  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final subtotal = appState.cartSubtotal;
    final paid = double.tryParse(_paidCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    final change = paid - subtotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout & Bayar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Total Belanja', style: Theme.of(context).textTheme.labelLarge),
          Text(_currency.format(subtotal),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 20),

          Text('Data Kastamer (opsional)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // Autocomplete dari daftar Klien tersimpan - kalau nama yang
          // diketik cocok dengan klien lama, tinggal pilih dan Alamat
          // otomatis terisi. Kalau tidak dipilih (nama baru), klien baru
          // otomatis tercatat saat transaksi disimpan (lihat _processPayment).
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
                onChanged: (v) => _custNameCtrl.text = v,
                decoration: const InputDecoration(
                  labelText: 'Nama Kastamer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );
            },
            onSelected: (client) {
              _custNameCtrl.text = client.name;
              if (client.address.isNotEmpty) _custAddrCtrl.text = client.address;
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _custAddrCtrl,
            decoration: const InputDecoration(
              labelText: 'Alamat Kastamer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          Text('Pembayaran', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _paidCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Jumlah Dibayar',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Kembalian: '),
              Text(
                _currency.format(change < 0 ? 0 : change),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (paid > 0 && paid < subtotal)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Jumlah bayar kurang dari total.',
                  style: TextStyle(color: Colors.red, fontSize: 12)),
            ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_processing || paid < subtotal) ? null : _processPayment,
            icon: _processing
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print),
            label: Text(_processing ? 'Memproses...' : 'SIMPAN & CETAK STRUK'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    setState(() => _processing = true);
    final appState = context.read<AppState>();
    final subtotal = appState.cartSubtotal;
    final paid = double.tryParse(
            _paidCtrl.text.replaceAll('.', '').replaceAll(',', '')) ??
        0;

    // PosTransaction & StoreSettings dibuat di luar try supaya tetap bisa
    // dipakai untuk tombol "Coba Cetak Lagi" pada dialog di bawah, tanpa
    // perlu query ulang ke database.
    late final PosTransaction trx;
    late final StoreSettings settings;
    bool printed = false;
    bool connected = false;
    String? errorMessage;
    String? printErrorDetail;

    try {
      final trxNo = await DatabaseHelper.instance.nextTrxNo();
      trx = PosTransaction(
        trxNo: trxNo,
        trxDate: DateTime.now(),
        cashierName: appState.activeCashier?.name ?? '-',
        customerName: _custNameCtrl.text.trim(),
        customerAddress: _custAddrCtrl.text.trim(),
        subtotal: subtotal,
        discount: 0,
        total: subtotal,
        paid: paid,
        change: paid - subtotal,
        items: appState.cart.map((l) => l.toTransactionItem()).toList(),
      );

      // Simpan transaksi dulu - ini yang PALING PENTING untuk tidak hilang,
      // jadi dipisah dari proses cetak yang lebih rawan gagal (Bluetooth).
      await DatabaseHelper.instance.saveTransaction(trx);

      // Klien otomatis tercatat di daftar Klien bersama kalau namanya
      // diisi (dan belum ada) - supaya bisa dipakai lagi lewat autocomplete
      // di transaksi berikutnya, baik kasir maupun Tanda Terima.
      if (trx.customerName.trim().isNotEmpty) {
        await DatabaseHelper.instance.upsertClientGetId(
          name: trx.customerName,
          address: trx.customerAddress,
        );
      }

      settings = await DatabaseHelper.instance.getSettings();

      // isConnected() sekarang sudah mencoba beberapa kali secara internal
      // (lihat BluetoothPrinterService) - timeout luar ini cuma jaring
      // pengaman terakhir, dilonggarkan supaya tidak memotong di tengah
      // proses percobaan ulang tersebut.
      try {
        connected = await BluetoothPrinterService.instance
            .isConnected()
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      } catch (_) {
        connected = false;
      }

      if (connected) {
        try {
          printed = await ReceiptService.printReceipt(trx: trx, settings: settings)
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

    // Kalau gagal SEBELUM transaksi sempat tersimpan (mis. gagal generate
    // nomor transaksi / gagal saveTransaction), beri tahu apa adanya dan
    // JANGAN kosongkan keranjang - supaya kasir bisa coba SIMPAN lagi.
    if (errorMessage != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Transaksi Gagal Disimpan'),
          content: Text(
            'Terjadi kesalahan saat menyimpan transaksi:\n$errorMessage\n\n'
            'Keranjang belanja TIDAK dikosongkan. Silakan coba lagi.',
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

    appState.clearCart();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(printed
                ? 'Transaksi Berhasil'
                : connected
                    ? 'Transaksi Tersimpan (Cetak Gagal)'
                    : 'Transaksi Tersimpan (Printer Belum Terhubung)'),
            content: Text(
              printed
                  ? 'Struk "${trx.trxNo}" berhasil dicetak.'
                  : connected
                      ? 'Data transaksi sudah tersimpan, namun struk gagal dicetak.'
                          '${printErrorDetail != null ? '\n\nDetail: $printErrorDetail' : ''}'
                          '\n\nCoba tombol "Cetak Lagi" di bawah, atau cetak ulang'
                          ' nanti dari menu Riwayat Transaksi.'
                      : 'Data transaksi sudah tersimpan, namun struk belum tercetak.\n\n'
                          'Kalau printer sudah/baru saja terhubung, tekan tombol'
                          ' "Cetak Lagi" di bawah ini - tidak perlu pindah ke menu'
                          ' Riwayat Transaksi.',
            ),
            actions: [
              if (!printed)
                TextButton.icon(
                  icon: _retryingPrint
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print, size: 18),
                  label: Text(_retryingPrint ? 'Mencetak...' : 'Cetak Lagi'),
                  onPressed: _retryingPrint
                      ? null
                      : () async {
                          setDialogState(() => _retryingPrint = true);
                          bool ok = false;
                          try {
                            ok = await ReceiptService.printReceipt(
                                    trx: trx, settings: settings)
                                .timeout(const Duration(seconds: 10),
                                    onTimeout: () => false);
                          } catch (e) {
                            printErrorDetail = e.toString();
                          }
                          setDialogState(() {
                            _retryingPrint = false;
                            printed = ok;
                            connected = true;
                            if (!ok && printErrorDetail == null) {
                              printErrorDetail =
                                  'Percobaan cetak ulang masih gagal. Pastikan '
                                  'printer menyala & tersambung di menu Pengaturan.';
                            }
                          });
                        },
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // tutup dialog
                  Navigator.of(context).pop(); // kembali ke layar Kasir
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }
}
