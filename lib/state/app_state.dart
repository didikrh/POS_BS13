import 'package:flutter/foundation.dart';

import '../models/cashier.dart';
import '../models/product.dart';
import '../models/transaction_item.dart';

class CartLine {
  final Product product;
  double qty;
  CartLine({required this.product, this.qty = 1});
  double get subtotal => product.price * qty;

  TransactionItem toTransactionItem() => TransactionItem(
        productId: product.id,
        productName: product.name,
        price: product.price,
        qty: qty,
      );
}

/// State global sederhana (Provider/ChangeNotifier) - cukup untuk skala
/// aplikasi POS toko kecil, tidak perlu state-management yang berat.
class AppState extends ChangeNotifier {
  Cashier? _activeCashier;
  Cashier? get activeCashier => _activeCashier;
  bool get isLoggedIn => _activeCashier != null;

  void login(Cashier cashier) {
    _activeCashier = cashier;
    notifyListeners();
  }

  void logout() {
    _activeCashier = null;
    _cart.clear();
    notifyListeners();
  }

  final List<CartLine> _cart = [];
  List<CartLine> get cart => List.unmodifiable(_cart);

  double get cartSubtotal =>
      _cart.fold(0, (sum, line) => sum + line.subtotal);

  void addProduct(Product p, {double qty = 1}) {
    final idx = _cart.indexWhere((l) => l.product.id == p.id);
    if (idx >= 0) {
      _cart[idx].qty += qty;
    } else {
      _cart.add(CartLine(product: p, qty: qty));
    }
    notifyListeners();
  }

  void updateQty(int index, double qty) {
    if (qty <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index].qty = qty;
    }
    notifyListeners();
  }

  void removeAt(int index) {
    _cart.removeAt(index);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }
}
