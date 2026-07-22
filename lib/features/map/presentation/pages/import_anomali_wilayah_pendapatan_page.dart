import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/usaha_pendapatan_item.dart';
import '../../data/services/anomali_wilayah_service.dart';

/// Impor anomali wilayah - Pengecekan Pendapatan.
/// Admin memasukkan usaha dengan total_pendapatan ekstrem sebagai anomali
/// UW1 (Pendapatan Anomali Tinggi) / UW2 (Pendapatan Anomali Rendah).
class ImportAnomaliWilayahPendapatanPage extends StatefulWidget {
  const ImportAnomaliWilayahPendapatanPage({super.key});

  @override
  State<ImportAnomaliWilayahPendapatanPage> createState() =>
      _ImportAnomaliWilayahPendapatanPageState();
}

class _ImportAnomaliWilayahPendapatanPageState
    extends State<ImportAnomaliWilayahPendapatanPage> {
  final AnomaliWilayahService _service = AnomaliWilayahService();
  final TextEditingController _batasController = TextEditingController();

  String _jenis = 'tinggi'; // 'tinggi' | 'rendah'
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  List<UsahaPendapatanItem> _items = [];
  final Set<String> _selected = {};
  bool _hasSearched = false;

  static const Color _accent = Color(0xFF1D8F5A);
  static const String _fasihSurveyId = 'fd68e454-ba45-4b85-8205-f3bf777ded24';

  Future<void> _openFasih(String assignmentId) async {
    if (assignmentId.isEmpty) return;
    final uri = Uri.tryParse(
        'https://fasih-sm.bps.go.id/app/assignment/$_fasihSurveyId/$assignmentId/edit');
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka Fasih')),
      );
    }
  }

  @override
  void dispose() {
    _batasController.dispose();
    super.dispose();
  }

  String _formatRupiah(num v) {
    final s = v.round().abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}Rp $buf';
  }

  Future<void> _tampilkan() async {
    final batas = num.tryParse(_batasController.text.replaceAll('.', '').trim());
    if (batas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nilai ambang pendapatan dulu.')),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _selected.clear();
      _hasSearched = true;
    });
    try {
      final items = await _service.fetchUsahaPendapatanEkstrem(
        jenis: _jenis,
        batas: batas,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _masukkan() async {
    final chosen =
        _items.where((e) => _selected.contains(e.key)).toList();
    if (chosen.isEmpty) return;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await _service.insertAnomaliUsahaPendapatan(
        jenis: _jenis,
        items: chosen,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$n usaha dimasukkan sebagai anomali.')),
      );
      setState(() {
        _selected.clear();
        _isSaving = false;
      });
      await _tampilkan(); // segarkan untuk memperbarui tanda "sudah anomali"
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal memasukkan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final kategoriLabel = _jenis == 'tinggi'
        ? 'UW1 - Pendapatan Anomali Tinggi'
        : 'UW2 - Pendapatan Anomali Rendah';
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Pengecekan Pendapatan'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildControls(kategoriLabel),
            Expanded(child: _buildBody()),
            if (_selected.isNotEmpty) _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(String kategoriLabel) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'tinggi',
                label: Text('Tertinggi'),
                icon: Icon(Icons.trending_up_rounded),
              ),
              ButtonSegment(
                value: 'rendah',
                label: Text('Terendah'),
                icon: Icon(Icons.trending_down_rounded),
              ),
            ],
            selected: {_jenis},
            onSelectionChanged: (s) => setState(() {
              _jenis = s.first;
              _items = [];
              _selected.clear();
              _hasSearched = false;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _batasController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: _jenis == 'tinggi'
                        ? 'Batas bawah (pendapatan ≥ ...)'
                        : 'Batas atas (pendapatan ≤ ...)',
                    prefixText: 'Rp ',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _tampilkan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Tampilkan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kategori: $kategoriLabel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (!_hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Isi nilai ambang lalu tekan Tampilkan untuk melihat usaha '
            'dengan pendapatan ekstrem.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada usaha yang memenuhi ambang.',
          style: TextStyle(color: Colors.blueGrey[600]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildRow(_items[index], index),
    );
  }

  Widget _buildRow(UsahaPendapatanItem item, int index) {
    final checked = _selected.contains(item.key);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          if (checked) {
            _selected.remove(item.key);
          } else {
            _selected.add(item.key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: checked,
                activeColor: _accent,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(item.key);
                  } else {
                    _selected.remove(item.key);
                  }
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}. ${item.namaSubjek}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF10243E),
                            ),
                          ),
                        ),
                        if (item.sudahAnomali)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Sudah anomali',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.wilayahLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatRupiah(item.totalPendapatan),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                color: const Color(0xFF1F6FEB),
                tooltip: 'Buka di Fasih',
                onPressed: () => _openFasih(item.assignmentId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _masukkan,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.playlist_add_check_rounded),
          label: Text(
            _isSaving
                ? 'Memasukkan...'
                : 'Masukkan Anomali (${_selected.length})',
          ),
        ),
      ),
    );
  }
}
