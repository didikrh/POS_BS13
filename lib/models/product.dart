class Product {
  final int? id;
  final String code; // kode barcode/QR barang (unik)
  final String name;
  final double price;
  final double stock;
  final String unit; // pcs, kg, dus, dll

  Product({
    this.id,
    required this.code,
    required this.name,
    required this.price,
    this.stock = 0,
    this.unit = 'pcs',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'price': price,
        'stock': stock,
        'unit': unit,
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as int?,
        code: m['code'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        stock: (m['stock'] as num).toDouble(),
        unit: m['unit'] as String,
      );

  Product copyWith({
    int? id,
    String? code,
    String? name,
    double? price,
    double? stock,
    String? unit,
  }) =>
      Product(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        unit: unit ?? this.unit,
      );
}
