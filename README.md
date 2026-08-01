# Aplikasi POS Android - Printer Thermal 58mm Bluetooth

Aplikasi kasir (Point of Sales) Android dibangun dengan **Flutter**,
mendukung cetak struk & label barang lewat **printer thermal 58mm via
Bluetooth**, identifikasi barang dengan **ketik manual atau scan
barcode/QR Code**, dan database transaksi **SQLite (sqflite)** yang
ringan.

## 1. Struktur Project

```
pos_thermal_app/
├── pubspec.yaml                  # daftar dependensi
├── .github/
│   └── workflows/
│       └── build_apk.yml         # GitHub Actions - compile APK otomatis di cloud
├── tool/
│   └── patch_android.py          # patch otomatis permission & minSdkVersion
├── docs/
│   └── AndroidManifest_REFERENCE.xml   # referensi permission (fallback manual)
├── (android/ SENGAJA TIDAK ADA di repo — dibuat otomatis saat build
│    lewat `flutter create .`, baik di GitHub Actions maupun lokal.
│    Jangan buat folder android/ kosong/manual di repo, karena akan
│    membuat langkah "flutter create" di CI ter-skip.)
└── lib/
    ├── main.dart                 # entry point + routing
    ├── models/                   # Product, Cashier, StoreSettings, PosTransaction, TransactionItem
    ├── db/
    │   └── database_helper.dart  # SQLite (sqflite) - schema & query
    ├── services/
    │   ├── escpos_builder.dart          # builder perintah ESC/POS mentah
    │   ├── qr_raster.dart               # encoder QR Code -> bitmap (murni Dart)
    │   ├── barcode_raster.dart          # encoder Barcode 1D -> bitmap
    │   ├── bluetooth_printer_service.dart # koneksi printer Bluetooth Classic
    │   ├── receipt_service.dart         # bangun & cetak struk (header/footer kustom)
    │   └── label_service.dart           # cetak label identitas barang
    ├── state/
    │   └── app_state.dart        # sesi kasir aktif + keranjang belanja (Provider)
    └── screens/
        ├── login_screen.dart
        ├── home_screen.dart              # bottom navigation
        ├── pos_screen.dart               # kasir: cari/scan barang, keranjang
        ├── scan_screen.dart              # kamera scan barcode/QR (reusable)
        ├── checkout_screen.dart          # data pelanggan, bayar, cetak struk
        ├── product_list_screen.dart      # master produk
        ├── product_form_screen.dart      # tambah/edit produk + scan kode
        ├── settings_screen.dart          # info toko + pairing printer
        └── transaction_history_screen.dart # riwayat + cetak ulang struk
```

## 2. Cara Compile TANPA Laptop Berat — via GitHub Actions

Kalau laptop kurang bertenaga untuk install Flutter SDK + compile
Android, semua proses build (`flutter create`, `pub get`, sampai
compile APK) bisa dijalankan otomatis di server GitHub (GitHub
Actions) — laptop Anda cukup punya **Git** saja, tidak perlu install
Flutter/Android Studio sama sekali.

Project ini sudah dilengkapi:
- `.github/workflows/build_apk.yml` — workflow otomatis.
- `tool/patch_android.py` — script yang otomatis menambahkan
  permission Kamera & Bluetooth serta mengatur `minSdkVersion`
  setelah `flutter create .` dijalankan di server (menggantikan
  langkah manual edit `AndroidManifest.xml`).

### Tahapan

1. **Buat akun GitHub** (kalau belum punya) di https://github.com,
   gratis.

2. **Buat repository baru** di GitHub:
   - Klik tombol **"+"** di kanan atas → **"New repository"**.
   - Isi nama repo, misal `pos-thermal-app`.
   - Pilih **Public** atau **Private** (keduanya dapat jatah GitHub
     Actions gratis; untuk repo publik malah tanpa batas menit).
   - **Jangan** centang "Add a README" (supaya tidak bentrok dengan
     folder project yang sudah ada) → klik **Create repository**.

3. **Install Git** di laptop (kalau belum ada): unduh dari
   https://git-scm.com/downloads, lalu install seperti biasa.

4. **Upload project ini ke GitHub** — buka folder `pos_thermal_app`
   lewat terminal/Command Prompt, lalu jalankan:
   ```
   cd pos_thermal_app
   git init
   git add .
   git commit -m "Initial commit - POS Thermal App"
   git branch -M main
   git remote add origin https://github.com/USERNAME_ANDA/pos-thermal-app.git
   git push -u origin main
   ```
   (Ganti `USERNAME_ANDA` dengan username GitHub Anda. Saat `git push`,
   Anda akan diminta login — ikuti instruksi di layar/browser yang
   muncul.)

5. **Build otomatis akan langsung berjalan** begitu `git push`
   selesai (karena workflow dipicu oleh `push` ke branch `main`).
   Untuk memantau prosesnya:
   - Buka repo Anda di browser → tab **"Actions"**.
   - Klik run job yang sedang berjalan ("Build Android APK") untuk
     melihat log secara real-time (mirip Delphi Build Output, tapi
     di browser).
   - Proses build biasanya memakan waktu **5-10 menit** untuk build
     pertama kali (lebih cepat di run berikutnya karena ada cache).

6. **Unduh APK hasil build**:
   - Setelah job selesai (tanda centang hijau ✅), klik run tsb.
   - Scroll ke bagian **"Artifacts"** di bawah halaman ringkasan run.
   - Klik **`pos-thermal-app-release-apk`** untuk mengunduh file
     `.zip` yang berisi `app-release.apk`.
   - Salin `app-release.apk` ke HP Android (lewat kabel USB, Google
     Drive, dsb.), lalu instal seperti APK biasa (aktifkan dulu
     "Izinkan dari sumber tidak dikenal" di pengaturan HP jika
     diminta).

7. **(Opsional) Bikin Release resmi dengan APK terlampir** — supaya
   ada link unduhan permanen (tidak perlu buka tab Actions tiap kali):
   ```
   git tag v1.0.0
   git push origin v1.0.0
   ```
   Setelah workflow selesai, buka tab **"Releases"** di repo GitHub —
   akan ada rilis `v1.0.0` dengan `app-release.apk` siap diunduh
   langsung link-nya, bisa dibagikan ke siapa pun tanpa perlu login
   GitHub.

8. **Update aplikasi di kemudian hari**: setiap kali Anda mengubah
   kode (`lib/`, dsb.) dan menjalankan `git add . && git commit -m "..."
   && git push`, GitHub Actions otomatis build ulang APK terbaru —
   tinggal unduh lagi dari tab Actions/Releases.

### Kalau Build Gagal

- Buka log di tab **Actions** → klik step yang gagal (biasanya
  ditandai ❌) untuk lihat pesan error detailnya (mirip panel
  "Messages" di Delphi).
- **Error "Your project requires a newer version of the Kotlin Gradle
  plugin"** → workflow ini sengaja **tidak mengunci versi Flutter
  tertentu** (`channel: 'stable'` saja, tanpa `flutter-version:`)
  supaya template proyek yang dibuat `flutter create` selalu memakai
  kombinasi Kotlin/AGP/Gradle yang sudah teruji kompatibel oleh tim
  Flutter. Kalau Anda (atau versi lama file ini) sempat mengunci ke
  versi Flutter tertentu yang sudah lama, itu penyebab paling umum
  error ini — hapus baris `flutter-version:` di
  `.github/workflows/build_apk.yml` agar selalu pakai stable terbaru.
- Kalau `tool/patch_android.py` gagal menemukan pola di
  `build.gradle`/`build.gradle.kts` (ditandai `[WARN]` di log). Ini
  bisa terjadi kalau template Flutter versi baru mengubah format
  filenya — laporkan isi error tsb dan file `build.gradle*` yang
  di-generate, supaya scriptnya bisa disesuaikan.
- **`[ERROR] Tidak ditemukan: .../AndroidManifest.xml`** → pastikan
  repo Anda **tidak** menyertakan folder `android/` sama sekali
  (lihat diagram struktur di bagian 1) — folder ini harus dibuat
  otomatis oleh `flutter create .` saat build, bukan dikomit manual
  atau ikut ter-*push* dari percobaan sebelumnya.
- **Error "Namespace not specified" pada modul plugin tertentu**
  (mis. `blue_thermal_printer`) → ini terjadi karena AGP (Android
  Gradle Plugin) versi 8+ mewajibkan setiap modul Android
  mendeklarasikan `namespace`, sedangkan sejumlah plugin pub.dev lama
  yang sudah tidak di-*maintain* belum menambahkannya. Sudah
  ditangani otomatis oleh `tool/patch_android.py` (fungsi
  `patch_root_namespace_fix`), yang menyuntikkan `namespace` fallback
  untuk semua modul Android library yang belum mendeklarasikannya.
  Kalau muncul lagi untuk plugin LAIN dengan pesan serupa, biasanya
  cukup tunggu patch ini otomatis menanganinya juga (fix-nya berlaku
  untuk semua modul, bukan spesifik satu plugin saja) — tapi kalau
  tetap gagal, laporkan nama plugin & pesan errornya.

## 3. Cara Menjalankan Secara Lokal (Alternatif, jika laptop mumpuni)

Project ini berisi **kode Dart (`lib/`) dan `pubspec.yaml`**, tapi
folder native `android/` (Gradle, build.gradle, dsb.) dan `ios/` belum
di-generate penuh (itu ribuan baris boilerplate yang otomatis dibuat
Flutter). Langkahnya:

1. **Install Flutter SDK** (jika belum): https://docs.flutter.dev/get-started/install
2. Salin folder `pos_thermal_app` ini ke komputer Anda, lalu di terminal:
   ```
   cd pos_thermal_app
   flutter create . --project-name pos_thermal_app --org com.tokoanda
   ```
   Perintah ini akan membuat folder `android/`, `ios/`, dll secara
   otomatis **tanpa menimpa** `lib/` dan `pubspec.yaml` yang sudah ada.
3. Jalankan patch otomatis (permission Kamera/Bluetooth +
   `minSdkVersion`) — script yang sama persis dengan yang dipakai
   GitHub Actions, supaya hasilnya konsisten:
   ```
   python3 tool/patch_android.py
   ```
   Kalau tidak ada Python terinstall, ikuti manual lewat referensi di
   `docs/AndroidManifest_REFERENCE.xml` sebagai gantinya.
4. Install dependensi:
   ```
   flutter pub get
   ```
5. Jalankan ke HP Android (harus device fisik, karena emulator umumnya
   tidak punya Bluetooth & kamera yang berfungsi penuh):
   ```
   flutter run
   ```

## 4. Alur Pemakaian

1. **Login kasir** — default `username: kasir1`, `PIN: 1234` (bisa
   ditambah kasir lain langsung lewat tabel `cashiers` atau
   dikembangkan lebih lanjut jadi layar Master Kasir).
2. **Pairing printer** — di HP Android, pasangkan (pairing) printer
   thermal 58mm lewat **Pengaturan Bluetooth bawaan HP** terlebih
   dahulu (di luar aplikasi ini, standar OS). Setelah itu, buka menu
   **Pengaturan → Printer Thermal Bluetooth** di aplikasi, pilih
   printer dari daftar untuk **connect**.
3. **Atur info toko** — nama & alamat toko, ucapan footer struk,
   lebar kertas (58/80mm) di menu **Pengaturan**.
4. **Tambah barang** — menu **Produk**, isi kode (bisa diketik manual
   atau di-scan dari barcode/QR yang sudah ada di kemasan barang),
   nama, harga, stok.
5. **Transaksi** — menu **Kasir**:
   - Ketik nama/kode di kolom pencarian lalu tap barang untuk
     menambah ke keranjang (**cara manual**), ATAU
   - Tap tombol **Scan** untuk memindai barcode/QR barang dengan
     kamera (**cara scan**) — barang otomatis masuk keranjang.
   - Atur qty, lalu tekan **BAYAR**.
6. **Checkout** — isi data pelanggan (opsional), jumlah dibayar,
   tekan **SIMPAN & CETAK STRUK** — transaksi tersimpan ke database
   dan struk otomatis tercetak jika printer sedang terhubung.
7. **Cetak label barang** — di menu **Produk**, tekan ikon printer
   pada barang untuk mencetak label (pilih Barcode 1D atau QR Code)
   yang bisa ditempel di kemasan, lalu di-scan kembali saat transaksi.
8. **Riwayat transaksi** — lihat transaksi per rentang tanggal, cetak
   ulang struk kapan saja.

## 5. Kustomisasi Struk (Header & Footer)

Header struk (bisa diubah di menu Pengaturan / kode `PosTransaction`
& `StoreSettings`):
- Nama & alamat toko
- Tanggal transaksi (otomatis, waktu transaksi disimpan)
- Nama kasir (otomatis, dari sesi login)
- Nama & alamat pelanggan (diisi manual saat checkout, opsional)

Footer struk (`receipt_service.dart`):
- **QR Code** berisi info transaksi (`No. Struk, tanggal, total,
  kasir`) — bisa dipindai untuk verifikasi/lookup transaksi di
  kemudian hari.
- Ucapan/*greeting* bertema terima kasih, teksnya bisa diubah bebas
  di menu Pengaturan.

Kalau ingin format lain (misal barcode 1D untuk footer, bukan QR),
tinggal ganti pemanggilan `b.qrImage(...)` di `receipt_service.dart`
menjadi `b.barcodeBitmap(BarcodeRaster.toBitmap(...))` seperti pola
yang dipakai di `label_service.dart`.

## 6. Kenapa SQLite (sqflite) untuk Database Transaksi?

Dipilih sebagai **paling ringan & tidak boros memori** untuk konteks
aplikasi POS mobile karena:

| Aspek | SQLite (sqflite) | Alternatif NoSQL (Hive/sembast) |
|---|---|---|
| Engine | Native OS (sudah ada di Android/iOS, tidak menambah ukuran APK signifikan) | Murni Dart, sedikit menambah ukuran APK |
| Cocok untuk | Data relasional (transaksi ↔ item, laporan agregat SUM/GROUP BY) | Data sederhana key-value, tanpa relasi kompleks |
| Query laporan (mis. omzet per tanggal) | Cepat & efisien lewat SQL native (`WHERE`, `GROUP BY`, index) | Harus load & hitung manual di Dart, lebih boros memori untuk data besar |
| Proses terpisah? | Tidak — embedded, in-process | Tidak — embedded, in-process |

**Kesimpulan**: untuk kebutuhan **transaksi POS yang punya relasi
(struk → daftar item) dan laporan**, SQLite adalah pilihan paling
efisien secara keseluruhan (bukan cuma soal ukuran file, tapi juga
kecepatan & memori saat query laporan). Index sudah ditambahkan pada
kolom tanggal transaksi (`idx_trx_date`) supaya laporan/riwayat tetap
cepat meski data sudah banyak.

Jika suatu saat kebutuhan berkembang jadi sangat sederhana tanpa
laporan sama sekali (misal cuma menyimpan log tanpa perlu filter/
agregat), **Hive** bisa dipertimbangkan karena sedikit lebih cepat
untuk operasi baca/tulis murni tanpa query kompleks — namun untuk
kasus POS dengan kebutuhan laporan, SQLite tetap direkomendasikan.

## 7. Cara Kerja Cetak (ESC/POS) — Kenapa Ditulis Manual?

`escpos_builder.dart` membangun perintah ESC/POS **byte mentah**
secara manual (bukan memakai package `esc_pos_bluetooth`/`esc_pos_utils`)
supaya:
- Kontrol penuh atas format (align, bold, ukuran teks, potong kertas)
  tanpa tergantung API package pihak ketiga yang bisa berubah versi.
- QR Code & Barcode dirender sendiri jadi **bitmap raster** (`qr_raster.dart`,
  `barcode_raster.dart`) lalu dikirim sebagai perintah `GS v 0` (raster
  bit image) — pendekatan ini paling **kompatibel ke berbagai merek
  printer 58mm** dibanding mengandalkan perintah QR/barcode native
  printer (`GS ( k`) yang dukungannya tidak seragam antar merek.

Transport (pengiriman byte ke printer) memakai `blue_thermal_printer`
karena printer thermal murah 58mm umumnya memakai profil **Bluetooth
Classic (SPP)**, bukan BLE.

## 8. Troubleshooting

- **Printer tidak muncul di daftar Pengaturan** → pastikan sudah
  di-*pairing* lebih dulu lewat Pengaturan Bluetooth bawaan HP (di
  luar aplikasi), baru akan muncul sebagai "paired device".
- **Gagal connect ke printer (Android 12+)** → pastikan permission
  `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` sudah di-*grant* (aplikasi akan
  meminta otomatis saat pertama kali refresh daftar printer di menu
  Pengaturan).
- **Hasil cetak QR/barcode terlalu besar/kecil atau terpotong** →
  sesuaikan parameter `scale` pada `b.qrImage(data, scale: ...)` di
  `receipt_service.dart`/`label_service.dart`, atau `widthPx`/`heightPx`
  pada `BarcodeRaster.toBitmap(...)` sesuai lebar kertas printer Anda.
- **Karakter aneh/kotak-kotak pada hasil cetak** → printer memakai
  code page yang tidak didukung. Coba tambahkan perintah `ESC t n`
  (`0x1B, 0x74, n`) di `EscPosBuilder.reset()` untuk memilih code page
  yang sesuai dengan manual printer Anda (nilai `n` berbeda-beda per
  merek printer).

## 9. Pengembangan Lanjutan yang Disarankan

- Master Kasir (CRUD, saat ini kasir baru harus ditambah manual ke
  tabel `cashiers`).
- Diskon per-item atau diskon transaksi (kolom `discount` sudah
  tersedia di skema, tinggal ditambahkan UI-nya).
- Laporan omzet harian/bulanan dalam bentuk grafik (bisa pakai
  package `fl_chart`, data agregat cukup diambil dari tabel
  `transactions` yang sudah ber-index tanggal).
- Backup/restore database (`sqflite` menyimpan file `.db` biasa di
  `getDatabasesPath()`, tinggal disalin/di-share via `share_plus`).
- Multi-cabang/sinkronisasi cloud, jika suatu saat perlu data
  terpusat antar toko (di luar cakupan "paling ringan" pada versi
  ini, karena akan menambah kompleksitas jaringan).
