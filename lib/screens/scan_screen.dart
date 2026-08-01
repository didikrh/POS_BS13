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

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  _CameraCheckState _permState = _CameraCheckState.checking;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
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
        _CameraCheckState.granted => Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                // Tanpa errorBuilder, kegagalan kamera (mis. sedang dipakai
                // aplikasi lain, driver kamera OEM bermasalah, dsb) hanya
                // tampil sebagai layar hitam tanpa keterangan. Dengan ini,
                // pesan error ASLI dari plugin ditampilkan ke layar supaya
                // penyebabnya bisa dipastikan & dilaporkan kalau masih ada.
                errorBuilder: (context, error, child) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 56, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text(
                            'Kamera gagal dibuka.',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _controller.start(),
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Overlay bidik sederhana
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
          ),
      },
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
