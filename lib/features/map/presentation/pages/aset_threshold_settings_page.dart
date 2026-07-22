import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/keluarga_aset_item.dart';
import '../../data/services/aset_thresholds.dart';

/// Pengaturan ambang aset (lokal). Nilai >= ambang dianggap anomali.
class AsetThresholdSettingsPage extends StatefulWidget {
  const AsetThresholdSettingsPage({super.key});

  @override
  State<AsetThresholdSettingsPage> createState() =>
      _AsetThresholdSettingsPageState();
}

class _AsetThresholdSettingsPageState
    extends State<AsetThresholdSettingsPage> {
  static const Color _accent = Color(0xFF9A3412);
  final Map<String, TextEditingController> _controllers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    for (final k in KeluargaAsetItem.asetKeys) {
      _controllers[k] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final map = await AsetThresholds.load();
    if (!mounted) return;
    setState(() {
      for (final k in KeluargaAsetItem.asetKeys) {
        _controllers[k]!.text = (map[k] ?? 1).toString();
      }
      _loading = false;
    });
  }

  Future<void> _simpan() async {
    final values = <String, int>{};
    for (final k in KeluargaAsetItem.asetKeys) {
      final v = int.tryParse(_controllers[k]!.text.trim());
      if (v == null || v < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Nilai ${KeluargaAsetItem.asetLabel[k]} harus angka ≥ 1')),
        );
        return;
      }
      values[k] = v;
    }
    await AsetThresholds.save(values);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ambang disimpan.')));
    Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    setState(() {
      for (final k in KeluargaAsetItem.asetKeys) {
        _controllers[k]!.text = (AsetThresholds.defaults[k] ?? 1).toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Ambang Aset'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Default',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Keluarga dengan aset ≥ ambang berikut akan ditandai '
                    'anomali. Pengaturan ini tersimpan di perangkat ini saja.',
                    style: TextStyle(color: Colors.blueGrey[600], height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  for (final k in KeluargaAsetItem.asetKeys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(KeluargaAsetItem.asetLabel[k] ?? k,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          const Text('≥ '),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _controllers[k],
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _simpan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Simpan'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
