import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/deposit_receipt.dart';
import '../services/deposit_receipt_service.dart';
import '../services/bluetooth_printer_service.dart';
import 'deposit_receipt_form_screen.dart';

class DepositReceiptListScreen extends StatefulWidget {
  const DepositReceiptListScreen({super.key});

  @override
  State<DepositReceiptListScreen> createState() => DepositReceiptListScreenState();
}

class DepositReceiptListScreenState extends State<DepositReceiptListScreen> {
  List<DepositReceipt> _list = [];
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
  int? _printingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Dipanggil dari HomeScreen setiap kali tab ini dipilih - sama seperti
  /// pola di TransactionHistoryScreen (IndexedStack menjaga tab tetap
  /// hidup, jadi initState() cuma jalan sekali di awal login).
  void refreshToIncludeToday() {
    final now = DateTime.now();
    if (_to.isBefore(now)) {
      _to = now;
    }
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseHelper.instance.getDepositReceiptsBetween(
      DateTime(_from.year, _from.month, _from.day),
      DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
    );
    if (!mounted) return;
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

  Future<void> _openForm() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DepositReceiptFormScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _reprint(DepositReceipt receipt) async {
    setState(() => _printingId = receipt.id);
    String? loadErrorMessage;
    String? printErrorDetail;
    bool connected = false;
    bool printed = false;

    try {
      final items =
          await DatabaseHelper.instance.getItemsForDepositReceipt(receipt.id!);
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
            receipt: DepositReceipt.fromMap(receipt.toMap(), items: items),
            settings: settings,
          ).timeout(const Duration(seconds: 10), onTimeout: () => false);
        } catch (e) {
          printed = false;
          printErrorDetail = e.toString();
        }
      }
    } catch (e) {
      loadErrorMessage = e.toString();
    } finally {
      if (mounted) setState(() => _printingId = null);
    }

    if (!mounted) return;

    if (loadErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal memuat data: $loadErrorMessage'),
      ));
      return;
    }

    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Printer belum terhubung. Sambungkan dulu di menu Pengaturan.'),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(printed
          ? 'Tanda Terima berhasil dicetak ulang.'
          : 'Gagal mencetak.${printErrorDetail != null ? ' Detail: $printErrorDetail' : ''}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanda Terima'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Ubah rentang tanggal',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${_dateFmt.format(_from).split(' ')[0]} - ${_dateFmt.format(_to).split(' ')[0]}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _list.isEmpty
                ? const Center(child: Text('Belum ada Tanda Terima pada rentang ini'))
                : ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (context, i) {
                      final r = _list[i];
                      return ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text('${r.receiptNo} - ${r.clientName}'),
                        subtitle: Text(
                            '${_dateFmt.format(r.receiptDate)}  |  ${r.operatorName}'),
                        trailing: _printingId == r.id
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(2.0),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.print, size: 20),
                                onPressed: () => _reprint(r),
                                tooltip: 'Cetak ulang',
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
