class StoreSettings {
  final int id; // selalu 1 (single-row settings)
  final String storeName;
  final String storeAddress;
  final String footerGreeting; // ucapan terima kasih di footer struk
  final String printerName;
  final String printerMac;
  final int paperWidthMm; // 58 (default) atau 80

  StoreSettings({
    this.id = 1,
    this.storeName = 'TOKO SAYA',
    this.storeAddress = 'Alamat toko belum diatur',
    this.footerGreeting = 'Terima kasih telah berbelanja :)',
    this.printerName = '',
    this.printerMac = '',
    this.paperWidthMm = 58,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_name': storeName,
        'store_address': storeAddress,
        'footer_greeting': footerGreeting,
        'printer_name': printerName,
        'printer_mac': printerMac,
        'paper_width_mm': paperWidthMm,
      };

  factory StoreSettings.fromMap(Map<String, dynamic> m) => StoreSettings(
        id: m['id'] as int,
        storeName: m['store_name'] as String,
        storeAddress: m['store_address'] as String,
        footerGreeting: m['footer_greeting'] as String,
        printerName: (m['printer_name'] as String?) ?? '',
        printerMac: (m['printer_mac'] as String?) ?? '',
        paperWidthMm: (m['paper_width_mm'] as int?) ?? 58,
      );

  StoreSettings copyWith({
    String? storeName,
    String? storeAddress,
    String? footerGreeting,
    String? printerName,
    String? printerMac,
    int? paperWidthMm,
  }) =>
      StoreSettings(
        id: id,
        storeName: storeName ?? this.storeName,
        storeAddress: storeAddress ?? this.storeAddress,
        footerGreeting: footerGreeting ?? this.footerGreeting,
        printerName: printerName ?? this.printerName,
        printerMac: printerMac ?? this.printerMac,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      );
}
