import 'package:flutter/material.dart';

import 'pos_screen.dart';
import 'product_list_screen.dart';
import 'transaction_history_screen.dart';
import 'deposit_receipt_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _posKey = GlobalKey<PosScreenState>();
  final _productKey = GlobalKey<ProductListScreenState>();
  final _historyKey = GlobalKey<TransactionHistoryScreenState>();
  final _depositKey = GlobalKey<DepositReceiptListScreenState>();

  late final _pages = [
    PosScreen(key: _posKey),
    ProductListScreen(key: _productKey),
    TransactionHistoryScreen(key: _historyKey),
    DepositReceiptListScreen(key: _depositKey),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // SEMUA tab di sini dipakai IndexedStack yang menjaga state tetap
          // hidup - initState()-nya hanya jalan sekali di awal login, jadi
          // data baru (mis. produk yang otomatis bertambah dari setoran
          // Tanda Terima di tab lain) TIDAK akan muncul tanpa refresh
          // manual ini setiap kali tab terkait dibuka.
          switch (i) {
            case 0:
              _posKey.currentState?.refreshProducts();
              break;
            case 1:
              _productKey.currentState?.refreshProducts();
              break;
            case 2:
              _historyKey.currentState?.refreshToIncludeToday();
              break;
            case 3:
              _depositKey.currentState?.refreshToIncludeToday();
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Kasir'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Produk'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Riwayat'),
          NavigationDestination(icon: Icon(Icons.assignment_turned_in), label: 'Titip Barang'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}
