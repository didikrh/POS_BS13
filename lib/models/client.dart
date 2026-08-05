/// Data klien/pelanggan/nasabah bersama - dipakai baik oleh transaksi
/// kasir (jual-beli) maupun Tanda Terima (titip/setor barang), supaya
/// tidak perlu mengetik ulang identitas klien yang sama berkali-kali.
class Client {
  final int? id;
  final String name;
  final String contact; // no. HP/telepon (opsional)
  final String address; // alamat (opsional)

  Client({
    this.id,
    required this.name,
    this.contact = '',
    this.address = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'contact': contact,
        'address': address,
      };

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as int?,
        name: m['name'] as String,
        contact: (m['contact'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
      );
}
