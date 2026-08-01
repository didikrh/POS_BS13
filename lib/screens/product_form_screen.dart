import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/product.dart';
import 'scan_screen.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _unitCtrl;
  bool get _isEdit => widget.product?.id != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _codeCtrl = TextEditingController(text: p?.code ?? '');
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(text: p != null && p.price > 0 ? p.price.toStringAsFixed(0) : '');
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toStringAsFixed(0) : '0');
    _unitCtrl = TextEditingController(text: p?.unit ?? 'pcs');
  }

  Future<void> _scanCode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scan Kode Barang')),
    );
    if (code != null) setState(() => _codeCtrl.text = code);
  }

  Future<void> _save() async {
    if (_codeCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kode dan Nama barang wajib diisi.')),
      );
      return;
    }

    final product = Product(
      id: widget.product?.id,
      code: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text) ?? 0,
      stock: double.tryParse(_stockCtrl.text) ?? 0,
      unit: _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim(),
    );

    try {
      if (_isEdit) {
        await DatabaseHelper.instance.updateProduct(product);
      } else {
        await DatabaseHelper.instance.insertProduct(product);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: kode barang mungkin sudah dipakai. ($e)')),
      );
    }
  }

  Future<void> _delete() async {
    if (widget.product?.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Produk?'),
        content: Text('Yakin ingin menghapus "${widget.product!.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.deleteProduct(widget.product!.id!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Produk' : 'Tambah Produk'),
        actions: [
          if (_isEdit)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: 'Kode Barcode / QR',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scanCode,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nama Barang', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Harga Jual', prefixText: 'Rp ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Satuan', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('SIMPAN')),
        ],
      ),
    );
  }
}
