class StoreSettings {
  final int id; // selalu 1 (single-row settings)
  final String storeName;
  final String storeAddress;
  final String footerGreeting; // ucapan terima kasih di footer struk
  final String printerName;
  final String printerMac;
  final int paperWidthMm; // 58 (default) atau 80

  /// Ukuran header nama toko di struk cetak:
  /// 0 = Normal (ukuran sama seperti teks lain)
  /// 1 = Sedang (2x tinggi saja, lebar normal) - DEFAULT
  /// 2 = Besar (2x tinggi DAN 2x lebar - versi lama yang dikeluhkan
  ///     "kebesaran" karena juga melebarkan tiap huruf, bukan cuma
  ///     meninggikan)
  final int headerSize;

  StoreSettings({
    this.id = 1,
    this.storeName = 'TOKO SAYA',
    this.storeAddress = 'Alamat toko belum diatur',
    this.footerGreeting = 'Terima kasih telah berbelanja :)',
    this.printerName = '',
    this.printerMac = '',
    this.paperWidthMm = 58,
    this.headerSize = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_name': storeName,
        'store_address': storeAddress,
        'footer_greeting': footerGreeting,
        'printer_name': printerName,
        'printer_mac': printerMac,
        'paper_width_mm': paperWidthMm,
        'header_size': headerSize,
      };

  factory StoreSettings.fromMap(Map<String, dynamic> m) => StoreSettings(
        id: m['id'] as int,
        storeName: m['store_name'] as String,
        storeAddress: m['store_address'] as String,
        footerGreeting: m['footer_greeting'] as String,
        printerName: (m['printer_name'] as String?) ?? '',
        printerMac: (m['printer_mac'] as String?) ?? '',
        paperWidthMm: (m['paper_width_mm'] as int?) ?? 58,
        // Kolom baru (header_size) mungkin belum ada nilainya kalau baris
        // ini disimpan SEBELUM migrasi database ditambahkan - default ke
        // 1 (Sedang) supaya tidak error di HP yang sudah pernah install
        // versi lama aplikasi ini.
        headerSize: (m['header_size'] as int?) ?? 1,
      );

  StoreSettings copyWith({
    String? storeName,
    String? storeAddress,
    String? footerGreeting,
    String? printerName,
    String? printerMac,
    int? paperWidthMm,
    int? headerSize,
  }) =>
      StoreSettings(
        id: id,
        storeName: storeName ?? this.storeName,
        storeAddress: storeAddress ?? this.storeAddress,
        footerGreeting: footerGreeting ?? this.footerGreeting,
        printerName: printerName ?? this.printerName,
        printerMac: printerMac ?? this.printerMac,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
        headerSize: headerSize ?? this.headerSize,
      );
}
