import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Layar scan barcode/QR generik. Kembalikan hasil scan (String) lewat
/// Navigator.pop(context, code). Dipakai untuk:
/// - identifikasi barang saat transaksi (POS Screen)
/// - lookup barang di Master Produk
class ScanScreen extends StatefulWidget {
  final String title;
  const ScanScreen({super.key, this.title = 'Scan Barcode / QR Code'});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _CameraCheckState { checking, granted, denied, permanentlyDenied }

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  // CATATAN PENTING: sebelumnya cameraResolution dipaksa ke 1280x720
  // dengan dugaan itu penyebab NullPointerException native saat CameraX
  // membaca karakteristik kamera. TERBUKTI DARI LAPANGAN cara itu TIDAK
  // mencegah crash yang sama (masih terjadi persis dengan cameraResolution
  // di-set). Kesimpulan: ini kemungkinan besar masalah CameraX/Camera2 HAL
  // yang SPESIFIK ke chipset/vendor perangkat tertentu (dikonfirmasi ada
  // laporan identik di GitHub issue resmi mobile_scanner untuk sejumlah
  // perangkat Android 11 ke bawah, tanpa solusi kode yang pasti berhasil
  // di semua kasus). Karena itu, konfigurasi dikembalikan ke default
  // CameraX (tanpa memaksa resolusi) - default ini yang paling teruji di
  // banyak perangkat berbeda.
  //
  // Sebagai jaring pengaman: error dari native TETAP ditangkap rapi lewat
  // errorBuilder/MobileScannerState.error (lihat _buildCameraError di
  // bawah) - aplikasi TIDAK crash total, hanya layar scan ini yang
  // menampilkan pesan. Selain itu SELURUH transaksi & pencarian produk di
  // aplikasi ini tetap bisa dilakukan lewat KETIK MANUAL tanpa scan sama
  // sekali, jadi kegagalan kamera di perangkat tertentu tidak menghentikan
  // operasional toko.
  late MobileScannerController _controller;
  bool _handled = false;
  _CameraCheckState _permState = _CameraCheckState.checking;

  @override
  void initState() {
    super.initState();
    // WAJIB: tanpa observer ini, kamera yang "beku"/layar hitam setelah
    // aplikasi sempat ke background (notifikasi masuk, layar dikunci,
    // pindah app sebentar) TIDAK PERNAH pulih sendiri - ini penyebab
    // paling umum laporan "kamera masih tidak bisa dipakai" yang berulang
    // terus, karena kamera adalah resource EKSKLUSIF di Android: begitu
    // OS mengambil alih sesi kamera saat di background, controller Dart
    // tidak otomatis tahu dan tidak menyalakannya kembali sendiri -
    // mobile_scanner TIDAK menangani ini secara otomatis, harus manual.
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController();
    _ensureCameraPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pola ini diambil PERSIS dari dokumentasi resmi mobile_scanner untuk
    // versi 5.2.3 (versi yang dikunci di pubspec.yaml project ini - bukan
    // dari halaman "latest" yang bisa saja API-nya sudah beda).
    // `isInitialized` (bukan `hasCameraPermission`, itu API versi 6.x+)
    // adalah guard supaya dialog izin kamera sendiri (yang juga memicu
    // perubahan lifecycle) tidak salah ditangani sebagai app
    // background/foreground beneran.
    if (!_controller.value.isInitialized) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.inactive:
        _controller.stop();
        break;
    }
  }

  /// Reset TOTAL: buang controller lama (yang state internalnya mungkin
  /// sudah korup akibat crash sebelumnya) dan buat instance baru dari nol,
  /// baru coba mulai kamera lagi. Retry sederhana (panggil ulang
  /// `.start()` pada controller yang sama) kadang tidak cukup kalau
  /// masalahnya ada di state internal controller yang sudah rusak.
  Future<void> _resetAndRetryCamera() async {
    final oldController = _controller;
    // PENTING: controller LAMA harus benar-benar dilepas (dispose) DULU,
    // baru controller BARU dibuat setelahnya - bukan sebaliknya. Kamera
    // Android cuma bisa dipakai SATU proses dalam satu waktu; kalau
    // controller baru dibuat SEBELUM yang lama melepas kameranya, dua
    // controller sempat berebut resource kamera yang sama secara
    // bersamaan, dan controller baru bisa gagal terbuka - membuat tombol
    // "Coba Lagi" terasa tidak pernah benar-benar menyelesaikan masalah.
    await oldController.dispose();
    if (!mounted) return;
    setState(() {
      _controller = MobileScannerController();
    });
  }

  /// Cek & minta izin kamera secara EKSPLISIT sebelum widget MobileScanner
  /// dibangun. Kenapa perlu ini padahal mobile_scanner "seharusnya" minta
  /// izin sendiri: di sejumlah perangkat (custom ROM/OEM tertentu, atau
  /// saat status izin ada di kondisi limited/provisional), plugin native
  /// gagal memicu dialog izin dan kamera cuma diam / layar hitam tanpa
  /// pesan apa pun. Dengan pengecekan manual di sini, kita bisa tahu PASTI
  /// apakah penyebabnya izin, dan menampilkan pesan/tombol yang sesuai -
  /// bukan cuma layar kosong yang membingungkan.
  Future<void> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      if (status.isGranted || status.isLimited) {
        _permState = _CameraCheckState.granted;
      } else if (status.isPermanentlyDenied) {
        _permState = _CameraCheckState.permanentlyDenied;
      } else {
        _permState = _CameraCheckState.denied;
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;

    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPermissionMessage() {
    final isPermanent = _permState == _CameraCheckState.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              isPermanent
                  ? 'Izin kamera diblokir permanen untuk aplikasi ini.\n'
                      'Buka Pengaturan > Aplikasi > Izin > Kamera, lalu aktifkan manual.'
                  : 'Aplikasi butuh izin kamera untuk memindai barcode/QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (isPermanent)
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Buka Pengaturan Aplikasi'),
              )
            else
              FilledButton(
                onPressed: _ensureCameraPermission,
                child: const Text('Coba Lagi'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: _permState == _CameraCheckState.granted
            ? [
                IconButton(
                  icon: const Icon(Icons.flash_on),
                  onPressed: () => _controller.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.cameraswitch),
                  onPressed: () => _controller.switchCamera(),
                ),
              ]
            : null,
      ),
      body: switch (_permState) {
        _CameraCheckState.checking =>
          const Center(child: CircularProgressIndicator()),
        _CameraCheckState.denied ||
        _CameraCheckState.permanentlyDenied =>
          _buildPermissionMessage(),
        _CameraCheckState.granted => ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, child) {
              // Kalau ada error dari controller, tampilkan HANYA pesan error
              // itu (layar penuh) - jangan dicampur dengan overlay kotak
              // bidik / teks instruksi supaya tidak membingungkan seperti
              // sebelumnya (pesan error tertutup teks lain).
              if (state.error != null) {
                return _buildCameraError(state.error!);
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error, child) =>
                        _buildCameraError(error),
                  ),
                  const _ScanOverlay(),
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Arahkan kamera ke barcode/QR Code barang',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        backgroundColor: Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      },
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Kamera gagal dibuka.',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Kode: ${error.errorCode}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
              const SizedBox(height: 4),
              SelectableText(
                error.errorDetails?.message ?? error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text(
                'Kamera pada sebagian perangkat memang bisa bermasalah.\n'
                'Anda tetap bisa lanjut dengan mengetik kode barang secara manual.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _resetAndRetryCamera,
                    child: const Text('Coba Lagi'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Ketik Manual Saja'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
