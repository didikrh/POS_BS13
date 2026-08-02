import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/product.dart';
import '../services/label_service.dart';
import '../services/excel_product_service.dart';
import 'product_form_screen.dart';
import 'scan_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  List<Product> _products = [];
  final _searchCtrl = TextEditingController();
  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? search}) async {
    final list = await DatabaseHelper.instance.getAllProducts(search: search);
    setState(() => _products = list);
  }

  Future<void> _openForm({Product? product}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (result == true) _load(search: _searchCtrl.text);
  }

  Future<void> _scanToFind() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scan untuk cari barang')),
    );
    if (code == null) return;
    final p = await DatabaseHelper.instance.getProductByCode(code);
    if (!mounted) return;
    if (p == null) {
      final tambah = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Barang belum terdaftar'),
          content: Text('Kode "$code" belum ada di Master Produk. Tambah baru?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tambah')),
          ],
        ),
      );
      if (tambah == true) {
        _openForm(product: Product(code: code, name: '', price: 0));
      }
    } else {
      _openForm(product: p);
    }
  }

  Future<void> _printLabel(Product p) async {
    final type = await showDialog<LabelType>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Cetak Label Sebagai'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, LabelType.barcode1D),
            child: const Text('Barcode 1D (Code128)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, LabelType.qr),
            child: const Text('QR Code'),
          ),
        ],
      ),
    );
    if (type == null) return;

    final ok = await LabelService.printProductLabel(p, type: type);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Label terkirim ke printer.' : 'Gagal mencetak - cek koneksi printer.'),
    ));
  }

  bool _excelBusy = false;

  Future<void> _exportTemplate() async {
    setState(() => _excelBusy = true);
    bool ok = false;
    String? error;
    try {
      ok = await ExcelProductService.exportTemplate();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _excelBusy = false);
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
    // ok == false tanpa error berarti user membatalkan dialog simpan - diam saja.
  }

  Future<void> _exportData() async {
    setState(() => _excelBusy = true);
    bool ok = false;
    String? error;
    try {
      ok = await ExcelProductService.exportData();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _excelBusy = false);
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal export data: $error')));
    } else if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Data produk berhasil diexport.')));
    }
  }

  Future<void> _importFromExcel() async {
    setState(() => _excelBusy = true);
    ExcelImportResult? result;
    String? error;
    try {
      result = await ExcelProductService.importFromExcel();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _excelBusy = false);
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

    await _load(search: _searchCtrl.text);
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
              Text('✅ ${result!.ditambahkan} produk baru ditambahkan.'),
              Text('🔄 ${result.diperbarui} produk diperbarui.'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master Produk'),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scanToFind),
          PopupMenuButton<String>(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Export / Import Excel',
            onSelected: (value) {
              switch (value) {
                case 'template':
                  _exportTemplate();
                  break;
                case 'export':
                  _exportData();
                  break;
                case 'import':
                  _importFromExcel();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Export Template Kosong'),
                  subtitle: Text('Untuk diisi lalu diimpor kembali'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Export Data Saat Ini'),
                  subtitle: Text('Semua produk yang sudah tersimpan'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('Import dari Excel'),
                  subtitle: Text('Tambah/perbarui banyak produk sekaligus'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: _excelBusy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari nama/kode barang...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (v) => _load(search: v),
            ),
          ),
          Expanded(
            child: _products.isEmpty
                ? const Center(child: Text('Belum ada produk'))
                : ListView.separated(
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _products[i];
                      return ListTile(
                        title: Text(p.name.isEmpty ? '(belum diberi nama)' : p.name),
                        subtitle: Text('${p.code}  •  ${_currency.format(p.price)}  •  Stok ${p.stock.toStringAsFixed(0)} ${p.unit}'),
                        onTap: () => _openForm(product: p),
                        trailing: IconButton(
                          icon: const Icon(Icons.print_outlined),
                          tooltip: 'Cetak label',
                          onPressed: () => _printLabel(p),
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
