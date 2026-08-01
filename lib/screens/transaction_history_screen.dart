import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/pos_transaction.dart';
import '../services/receipt_service.dart';
import '../services/bluetooth_printer_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  List<PosTransaction> _list = [];
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseHelper.instance.getTransactionsBetween(
      DateTime(_from.year, _from.month, _from.day),
      DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
    );
    setState(() => _list = list);
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  Future<void> _reprint(PosTransaction trx) async {
    final items = await DatabaseHelper.instance.getItemsForTransaction(trx.id!);
    final settings = await DatabaseHelper.instance.getSettings();
    final connected = await BluetoothPrinterService.instance.isConnected();

    if (!connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Printer belum terhubung. Sambungkan dulu di menu Pengaturan.'),
      ));
      return;
    }

    final ok = await ReceiptService.printReceipt(
      trx: PosTransaction.fromMap(trx.toMap(), items: items),
      settings: settings,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Struk berhasil dicetak ulang.' : 'Gagal mencetak.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final totalOmzet = _list.fold<double>(0, (sum, t) => sum + t.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickRange),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat('dd/MM/yyyy').format(_from)} - ${DateFormat('dd/MM/yyyy').format(_to)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text('Total Omzet: ${_currency.format(totalOmzet)}  (${_list.length} transaksi)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _list.isEmpty
                ? const Center(child: Text('Tidak ada transaksi pada periode ini'))
                : ListView.separated(
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = _list[i];
                      return ListTile(
                        title: Text(t.trxNo),
                        subtitle: Text(
                            '${_dateFmt.format(t.trxDate)} • Kasir: ${t.cashierName}'
                            '${t.customerName.isNotEmpty ? ' • ${t.customerName}' : ''}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_currency.format(t.total),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.print, size: 20),
                              onPressed: () => _reprint(t),
                              tooltip: 'Cetak ulang struk',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
