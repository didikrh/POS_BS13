import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/pos_transaction.dart';
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

          Text('Data Pelanggan (opsional)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _custNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Pelanggan',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _custAddrCtrl,
            decoration: const InputDecoration(
              labelText: 'Alamat Pelanggan',
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

    final trxNo = await DatabaseHelper.instance.nextTrxNo();
    final trx = PosTransaction(
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

    await DatabaseHelper.instance.saveTransaction(trx);

    final settings = await DatabaseHelper.instance.getSettings();
    final connected = await BluetoothPrinterService.instance.isConnected();

    bool printed = false;
    if (connected) {
      printed = await ReceiptService.printReceipt(trx: trx, settings: settings);
    }

    if (!mounted) return;
    setState(() => _processing = false);
    appState.clearCart();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(printed
            ? 'Transaksi Berhasil'
            : connected
                ? 'Transaksi Tersimpan (Cetak Gagal)'
                : 'Transaksi Tersimpan (Printer Belum Terhubung)'),
        content: Text(
          printed
              ? 'Struk "${trx.trxNo}" berhasil dicetak.'
              : 'Data transaksi sudah tersimpan, namun struk belum tercetak. '
                  'Sambungkan printer di menu Pengaturan lalu cetak ulang dari Riwayat Transaksi.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // tutup dialog
              Navigator.of(context).pop(); // kembali ke layar Kasir
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
