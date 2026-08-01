class TransactionItem {
  final int? id;
  final int? transactionId;
  final int? productId;
  final String productName;
  final double price;
  final double qty;
  double get subtotal => price * qty;

  TransactionItem({
    this.id,
    this.transactionId,
    this.productId,
    required this.productName,
    required this.price,
    required this.qty,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'transaction_id': transactionId,
        'product_id': productId,
        'product_name': productName,
        'price': price,
        'qty': qty,
        'subtotal': subtotal,
      };

  factory TransactionItem.fromMap(Map<String, dynamic> m) => TransactionItem(
        id: m['id'] as int?,
        transactionId: m['transaction_id'] as int?,
        productId: m['product_id'] as int?,
        productName: m['product_name'] as String,
        price: (m['price'] as num).toDouble(),
        qty: (m['qty'] as num).toDouble(),
      );
}
