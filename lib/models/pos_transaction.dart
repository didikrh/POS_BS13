import 'transaction_item.dart';

class PosTransaction {
  final int? id;
  final String trxNo;
  final DateTime trxDate;
  final String cashierName;
  final String customerName;
  final String customerAddress;
  final double subtotal;
  final double discount;
  final double total;
  final double paid;
  final double change;
  final List<TransactionItem> items;

  PosTransaction({
    this.id,
    required this.trxNo,
    required this.trxDate,
    required this.cashierName,
    this.customerName = '',
    this.customerAddress = '',
    required this.subtotal,
    this.discount = 0,
    required this.total,
    required this.paid,
    required this.change,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'trx_no': trxNo,
        'trx_date': trxDate.toIso8601String(),
        'cashier_name': cashierName,
        'customer_name': customerName,
        'customer_address': customerAddress,
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'paid': paid,
        'change': change,
      };

  factory PosTransaction.fromMap(Map<String, dynamic> m,
          {List<TransactionItem> items = const []}) =>
      PosTransaction(
        id: m['id'] as int?,
        trxNo: m['trx_no'] as String,
        trxDate: DateTime.parse(m['trx_date'] as String),
        cashierName: m['cashier_name'] as String,
        customerName: (m['customer_name'] as String?) ?? '',
        customerAddress: (m['customer_address'] as String?) ?? '',
        subtotal: (m['subtotal'] as num).toDouble(),
        discount: (m['discount'] as num).toDouble(),
        total: (m['total'] as num).toDouble(),
        paid: (m['paid'] as num).toDouble(),
        change: (m['change'] as num).toDouble(),
        items: items,
      );
}
