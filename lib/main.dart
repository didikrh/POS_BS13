import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'state/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  // WAJIB: seluruh aplikasi memakai DateFormat/NumberFormat dengan locale
  // 'id_ID' (format tanggal & mata uang Indonesia) di banyak tempat -
  // receipt_service.dart, transaction_history_screen.dart, pos_screen.dart,
  // checkout_screen.dart, dsb. Tanpa inisialisasi ini, PERTAMA KALI locale
  // 'id_ID' dipakai di manapun akan melempar
  // `LocaleDataException: Locale data has not been initialized`, yang
  // sebelumnya bikin: (1) daftar Riwayat Transaksi gagal dirender/blank
  // walau data-nya ada, dan (2) cetak struk gagal saat checkout.
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'POS Thermal 58mm',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
        ),
        home: const _RootRouter(),
      ),
    );
  }
}

/// Menampilkan LoginScreen jika belum ada kasir aktif, atau HomeScreen jika
/// sudah login.
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return appState.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
