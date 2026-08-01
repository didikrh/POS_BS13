import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import 'scan_screen.dart';
import 'checkout_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  List<Product> _results = [];
  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Future<void> _search(String q) async {
    final list = await DatabaseHelper.instance.getAllProducts(search: q);
    setState(() => _results = list);
  }

  Future<void> _scanAndAdd() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code == null) return;

    final product = await DatabaseHelper.instance.getProductByCode(code);
    if (!mounted) return;

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Barang dengan kode "$code" tidak ditemukan.'),
      ));
      return;
    }
    context.read<AppState>().addProduct(product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} ditambahkan.'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final cart = appState.cart;

    return Scaffold(
      appBar: AppBar(
        title: Text('Kasir - ${appState.activeCashier?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Keluar / Ganti Kasir',
            onPressed: () => context.read<AppState>().logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          // -------- Pencarian & Scan --------
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ketik nama/kode barang...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    onChanged: _search,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _scanAndAdd,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ),

          // -------- Hasil pencarian (tap untuk tambah manual) --------
          if (_results.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final p = _results[i];
                  return Card(
                    child: InkWell(
                      onTap: () => context.read<AppState>().addProduct(p),
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_currency.format(p.price)),
                            Text('Stok: ${p.stock.toStringAsFixed(0)} ${p.unit}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          const Divider(height: 1),

          // -------- Keranjang --------
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Keranjang masih kosong'))
                : ListView.separated(
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final line = cart[i];
                      return ListTile(
                        title: Text(line.product.name),
                        subtitle: Text(
                            '${_currency.format(line.product.price)} x ${line.qty.toStringAsFixed(line.qty == line.qty.roundToDouble() ? 0 : 2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => context
                                  .read<AppState>()
                                  .updateQty(i, line.qty - 1),
                            ),
                            Text(line.qty.toStringAsFixed(0)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => context
                                  .read<AppState>()
                                  .updateQty(i, line.qty + 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => context.read<AppState>().removeAt(i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // -------- Ringkasan & Bayar --------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Subtotal', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(_currency.format(appState.cartSubtotal),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: cart.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                            ),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                    child: const Text('BAYAR'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
