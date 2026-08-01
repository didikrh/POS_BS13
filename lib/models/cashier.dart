class Cashier {
  final int? id;
  final String username;
  final String pin; // PIN 4-6 digit, cukup untuk POS toko kecil
  final String name;

  Cashier({
    this.id,
    required this.username,
    required this.pin,
    required this.name,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'pin': pin,
        'name': name,
      };

  factory Cashier.fromMap(Map<String, dynamic> m) => Cashier(
        id: m['id'] as int?,
        username: m['username'] as String,
        pin: m['pin'] as String,
        name: m['name'] as String,
      );
}
