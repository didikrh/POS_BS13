import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/cashier.dart';
import '../state/app_state.dart';

class CashierManagementScreen extends StatefulWidget {
  const CashierManagementScreen({super.key});

  @override
  State<CashierManagementScreen> createState() => _CashierManagementScreenState();
}

class _CashierManagementScreenState extends State<CashierManagementScreen> {
  List<Cashier> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await DatabaseHelper.instance.getAllCashiers();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _openEditor({Cashier? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final pinCtrl = TextEditingController(text: existing?.pin ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Tambah Petugas/Kasir' : 'Edit Petugas/Kasir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nama (tampil di struk & Tanda Terima)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Username Login', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'PIN (4-6 digit)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  usernameCtrl.text.trim().isEmpty ||
                  pinCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Semua field wajib diisi.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    try {
      if (existing == null) {
        await DatabaseHelper.instance.insertCashier(Cashier(
          username: usernameCtrl.text.trim(),
          pin: pinCtrl.text.trim(),
          name: nameCtrl.text.trim(),
        ));
      } else {
        final updated = Cashier(
          id: existing.id,
          username: usernameCtrl.text.trim(),
          pin: pinCtrl.text.trim(),
          name: nameCtrl.text.trim(),
        );
        await DatabaseHelper.instance.updateCashier(updated);
        if (mounted) {
          context.read<AppState>().refreshActiveCashierIfMatches(updated);
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Data petugas tersimpan.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Petugas/Kasir')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const Center(child: Text('Belum ada data petugas/kasir'))
              : ListView.builder(
                  itemCount: _list.length,
                  itemBuilder: (context, i) {
                    final c = _list[i];
                    return ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(c.name),
                      subtitle: Text('Username: ${c.username}'),
                      trailing: const Icon(Icons.edit, size: 20),
                      onTap: () => _openEditor(existing: c),
                    );
                  },
                ),
    );
  }
}
