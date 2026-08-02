import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/pos_transaction.dart';
import '../services/receipt_service.dart';
import '../services/bluetooth_printer_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => TransactionHistoryScreenState();
}

class TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
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

  /// Dipanggil dari HomeScreen setiap kali tab "Riwayat" dipilih.
  ///
  /// KENAPA INI PERLU: navigasi bawah pakai IndexedStack supaya semua tab
  /// tetap "hidup" (state tidak hilang saat pindah tab) - konsekuensinya,
  /// initState() di layar ini HANYA jalan SATU KALI (saat login pertama
  /// kali), bukan setiap kali tab dibuka. Tanpa refresh eksplisit ini,
  /// transaksi baru yang dibuat SETELAH tab Riwayat pertama kali dibuka
  /// TIDAK AKAN PERNAH muncul sampai aplikasi ditutup & dibuka ulang -
  /// ini penyebab pasti laporan "riwayat tidak menampilkan transaksi yang
  /// baru saja tersimpan".
  void refreshToIncludeToday() {
    final now = DateTime.now();
    // Perluas _to ke "sekarang" kalau rentang yang dipilih user
    // sebelumnya sudah tidak mencakup hari ini (mis. user pernah pilih
    // rentang tanggal lampau lalu tidak diubah lagi).
    if (_to.isBefore(now)) {
      _to = now;
    }
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseHelper.instance.getTransactionsBetween(
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

  int? _printingTrxId;

  Future<void> _reprint(PosTransaction trx) async {
    setState(() => _printingTrxId = trx.id);
    String? loadErrorMessage;
    String? printErrorDetail;
    bool connected = false;
    bool printed = false;

    try {
      final items =
          await DatabaseHelper.instance.getItemsForTransaction(trx.id!);
      final settings = await DatabaseHelper.instance.getSettings();

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
          printed = await ReceiptService.printReceipt(
            trx: PosTransaction.fromMap(trx.toMap(), items: items),
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
      if (mounted) setState(() => _printingTrxId = null);
    }

    if (!mounted) return;

    if (loadErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal memuat data struk: $loadErrorMessage'),
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
          ? 'Struk berhasil dicetak ulang.'
          : 'Gagal mencetak.${printErrorDetail != null ? ' Detail: $printErrorDetail' : ''}'),
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
                            _printingTrxId == t.id
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
