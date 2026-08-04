/// Satu baris barang di dalam Tanda Terima (nama barang + berat).
class DepositReceiptItem {
  final int? id;
  final int? receiptId;
  final String itemName;
  final double weight;
  final String weightUnit; // 'kg' (default), 'gram', atau 'ton'
  final String notes;

  DepositReceiptItem({
    this.id,
    this.receiptId,
    required this.itemName,
    required this.weight,
    this.weightUnit = 'kg',
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'receipt_id': receiptId,
        'item_name': itemName,
        'weight': weight,
        'weight_unit': weightUnit,
        'notes': notes,
      };

  factory DepositReceiptItem.fromMap(Map<String, dynamic> m) =>
      DepositReceiptItem(
        id: m['id'] as int?,
        receiptId: m['receipt_id'] as int?,
        itemName: m['item_name'] as String,
        weight: (m['weight'] as num).toDouble(),
        weightUnit: (m['weight_unit'] as String?) ?? 'kg',
        notes: (m['notes'] as String?) ?? '',
      );
}

/// Tanda Terima: transaksi NON-KASIR untuk klien yang menyetor/menitipkan
/// barang (bukan transaksi jual-beli). Sengaja dipisah total dari
/// PosTransaction/tabel `transactions` karena sifat datanya beda (tidak ada
/// harga/uang, yang penting identitas klien, petugas, dan berat barang).
class DepositReceipt {
  final int? id;
  final String receiptNo; // mis. "TT-0001", terpisah dari nomor struk kasir
  final DateTime receiptDate;
  final String clientName;
  final String clientContact; // no. HP / alamat klien (opsional)
  final String operatorName; // petugas/kasir yang bertugas saat itu
  final String notes;
  final List<DepositReceiptItem> items;

  DepositReceipt({
    this.id,
    required this.receiptNo,
    required this.receiptDate,
    required this.clientName,
    this.clientContact = '',
    required this.operatorName,
    this.notes = '',
    this.items = const [],
  });

  double get totalWeightKg {
    double total = 0;
    for (final it in items) {
      switch (it.weightUnit) {
        case 'gram':
          total += it.weight / 1000;
          break;
        case 'ton':
          total += it.weight * 1000;
          break;
        default:
          total += it.weight;
      }
    }
    return total;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'receipt_no': receiptNo,
        'receipt_date': receiptDate.toIso8601String(),
        'client_name': clientName,
        'client_contact': clientContact,
        'operator_name': operatorName,
        'notes': notes,
      };

  factory DepositReceipt.fromMap(Map<String, dynamic> m,
          {List<DepositReceiptItem> items = const []}) =>
      DepositReceipt(
        id: m['id'] as int?,
        receiptNo: m['receipt_no'] as String,
        receiptDate: DateTime.parse(m['receipt_date'] as String),
        clientName: m['client_name'] as String,
        clientContact: (m['client_contact'] as String?) ?? '',
        operatorName: m['operator_name'] as String,
        notes: (m['notes'] as String?) ?? '',
        items: items,
      );
}
