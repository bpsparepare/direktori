import 'package:flutter/material.dart';

import '../../data/models/responden_sulit_item.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/services/responden_sulit_service.dart';

/// Halaman fitur "Responden Sulit".
///
/// Petugas (PPL) mendata responden yang sulit ditemui/diwawancarai dan boleh
/// memilih wilayah kerja. Entri otomatis terhubung ke PPL & PML wilayah itu,
/// sehingga PML dapat melihat dan ikut mengisi tindak lanjut. Filter role
/// dilakukan di sisi RPC (lihat RespondenSulitService).
class RespondenSulitPage extends StatefulWidget {
  const RespondenSulitPage({super.key});

  @override
  State<RespondenSulitPage> createState() => _RespondenSulitPageState();
}

class _RespondenSulitPageState extends State<RespondenSulitPage> {
  final RespondenSulitService _service = RespondenSulitService();
  final GroundcheckSupabaseService _gcService = GroundcheckSupabaseService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String _query = '';
  String? _role;
  List<RespondenSulitItem> _items = [];
  List<_WilayahOption> _wilayahOptions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await _gcService.fetchCurrentSe2026Profile();
      final wilayah = await _gcService.fetchCurrentUserWilayahTugas();
      final items = await _service.fetchList();
      if (!mounted) return;
      setState(() {
        _role = profile?.role;
        _wilayahOptions = wilayah
            .map(_WilayahOption.fromMap)
            .where((w) => w.id.isNotEmpty)
            .toList()
          ..sort((a, b) =>
              a.label.toLowerCase().compareTo(b.label.toLowerCase()));
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

  Future<void> _refresh() async {
    try {
      final items = await _service.fetchList();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<RespondenSulitItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final haystack = [
        item.nama,
        item.alamat,
        item.penjelasan,
        item.tindakLanjut,
        item.wilayahLabel,
        item.pplNama,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Future<void> _openForm({RespondenSulitItem? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RespondenSulitFormSheet(
        service: _service,
        wilayahOptions: _wilayahOptions,
        existing: existing,
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete(RespondenSulitItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus responden sulit?'),
        content: Text('Entri "${item.nama}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entri dihapus'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Responden Sulit'),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'responden_sulit_fab',
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverToBoxAdapter(child: _buildSearch()),
                        if (_filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmpty(),
                          )
                        else
                          SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 120),
                            sliver: SliverList.separated(
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) =>
                                  _buildCard(_filtered[index]),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    final isPml = _role == 'pengawas' || _role == 'admin';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.report_problem_outlined,
                color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Responden Sulit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isPml
                      ? 'Pantau responden sulit dari seluruh PPL di tim Anda dan isi tindak lanjut.'
                      : 'Catat responden yang sulit ditemui. Otomatis diteruskan ke PML Anda.',
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Cari nama, alamat, atau wilayah',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
        ),
      ),
    );
  }

  /// Kartu compact: hanya nama + baris ringkas (wilayah / alamat). Detail
  /// lengkap dibuka lewat tap.
  Widget _buildCard(RespondenSulitItem item) {
    final subtitle = item.wilayahLabel.isNotEmpty
        ? item.wilayahLabel
        : (item.alamat.isNotEmpty ? item.alamat : '—');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.person_pin_circle_outlined,
                  size: 22, color: Color(0xFF0F4C81)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10243E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.blueGrey[500],
                      ),
                    ),
                  ],
                ),
              ),
              if (item.tindakLanjut.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.checklist_rtl_rounded,
                      size: 18, color: Colors.green[600]),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: Colors.blueGrey[300]),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(RespondenSulitItem item) {
    final isPml = _role == 'pengawas' || _role == 'admin';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  item.nama,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10243E),
                  ),
                ),
                if (item.wilayahLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _chip(Icons.map_outlined, item.wilayahLabel),
                ],
                if (item.alamat.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _infoRow(Icons.location_on_outlined, 'Alamat', item.alamat),
                ],
                if (item.penjelasan.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _infoRow(Icons.sticky_note_2_outlined, 'Penjelasan',
                      item.penjelasan),
                ],
                if (item.tindakLanjut.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _infoRow(Icons.checklist_rtl_rounded, 'Tindak Lanjut',
                      item.tindakLanjut),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item.pplNama.isNotEmpty)
                      _tag('PPL: ${item.pplNama}', const Color(0xFF1D8F5A)),
                    if (isPml && item.pmlNama.isNotEmpty)
                      _tag('PML: ${item.pmlNama}', const Color(0xFFEA8600)),
                    if (item.createdByNama.isNotEmpty)
                      _tag('Oleh: ${item.createdByNama}',
                          const Color(0xFF5B6B7B)),
                  ],
                ),
                if (item.canEdit) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmDelete(item);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Hapus'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _openForm(existing: item);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F4C81),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F4C81).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0F4C81)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F4C81),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2D77D0)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[400],
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blueGrey[800],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isSearching = _query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.person_search_rounded,
                  size: 36, color: Color(0xFF2D77D0)),
            ),
            const SizedBox(height: 18),
            Text(
              isSearching
                  ? 'Data tidak ditemukan'
                  : 'Belum ada responden sulit',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Coba ganti kata kunci pencarian.'
                  : 'Tekan tombol Tambah untuk mencatat responden yang sulit ditemui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 50, color: Colors.red),
            const SizedBox(height: 14),
            const Text(
              'Gagal memuat data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opsi wilayah kerja untuk dropdown, dari se2026_wilayah_tugas.
class _WilayahOption {
  final String id;
  final String label;

  const _WilayahOption({required this.id, required this.label});

  factory _WilayahOption.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final nmSls = (map['nm_sls'] ?? '').toString().trim();
    // Sub-SLS = 2 digit terakhir id 16 digit (kode_desa10+sls4+subsls2).
    final subSls = id.length >= 16 ? id.substring(id.length - 2) : '';
    final parts = [
      RespondenSulitItem.formatSlsLabel(nmSls, subSls),
      (map['nm_desa'] ?? '').toString().trim(),
      (map['nm_kec'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    return _WilayahOption(
      id: id,
      label: parts.isEmpty ? id : parts.join(' · '),
    );
  }
}

class _RespondenSulitFormSheet extends StatefulWidget {
  final RespondenSulitService service;
  final List<_WilayahOption> wilayahOptions;
  final RespondenSulitItem? existing;

  const _RespondenSulitFormSheet({
    required this.service,
    required this.wilayahOptions,
    this.existing,
  });

  @override
  State<_RespondenSulitFormSheet> createState() =>
      _RespondenSulitFormSheetState();
}

class _RespondenSulitFormSheetState extends State<_RespondenSulitFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _namaCtrl;
  late final TextEditingController _alamatCtrl;
  late final TextEditingController _penjelasanCtrl;
  late final TextEditingController _tindakLanjutCtrl;
  String? _kodeWilayah;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _namaCtrl = TextEditingController(text: e?.nama ?? '');
    _alamatCtrl = TextEditingController(text: e?.alamat ?? '');
    _penjelasanCtrl = TextEditingController(text: e?.penjelasan ?? '');
    _tindakLanjutCtrl = TextEditingController(text: e?.tindakLanjut ?? '');
    final existingKode = e?.kodeWilayah ?? '';
    if (existingKode.isNotEmpty &&
        widget.wilayahOptions.any((w) => w.id == existingKode)) {
      _kodeWilayah = existingKode;
    }
  }

  @override
  void dispose() {
    _namaCtrl.dispose();
    _alamatCtrl.dispose();
    _penjelasanCtrl.dispose();
    _tindakLanjutCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.service.upsert(
        id: widget.existing?.id,
        kodeWilayah: _kodeWilayah,
        nama: _namaCtrl.text.trim(),
        alamat: _alamatCtrl.text.trim(),
        penjelasan: _penjelasanCtrl.text.trim(),
        tindakLanjut: _tindakLanjutCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    isEdit ? 'Edit Responden Sulit' : 'Tambah Responden Sulit',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (widget.wilayahOptions.isNotEmpty) ...[
                    _buildWilayahField(),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _namaCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Nama', Icons.person_outline),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _alamatCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        _decoration('Alamat', Icons.location_on_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _penjelasanCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration(
                        'Penjelasan', Icons.sticky_note_2_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tindakLanjutCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration(
                        'Tindak Lanjut', Icons.checklist_rtl_rounded),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C81),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWilayahField() {
    final selected = _kodeWilayah == null
        ? null
        : widget.wilayahOptions
            .cast<_WilayahOption?>()
            .firstWhere((w) => w?.id == _kodeWilayah, orElse: () => null);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickWilayah,
      child: InputDecorator(
        decoration: _decoration('Wilayah Kerja (opsional)', Icons.map_outlined)
            .copyWith(
          suffixIcon: _kodeWilayah == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => setState(() => _kodeWilayah = null),
                ),
        ),
        child: Text(
          selected?.label ?? '— Tidak dipilih —',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected == null ? Colors.blueGrey[400] : Colors.black87,
          ),
        ),
      ),
    );
  }

  Future<void> _pickWilayah() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<_WilayahOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WilayahPickerSheet(options: widget.wilayahOptions),
    );
    if (picked != null) {
      setState(() => _kodeWilayah = picked.id);
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF3F6FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// Bottom sheet pemilih wilayah dengan pencarian (daftar bisa ratusan).
class _WilayahPickerSheet extends StatefulWidget {
  final List<_WilayahOption> options;

  const _WilayahPickerSheet({required this.options});

  @override
  State<_WilayahPickerSheet> createState() => _WilayahPickerSheetState();
}

class _WilayahPickerSheetState extends State<_WilayahPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((w) => w.label.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Cari wilayah kerja...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF3F6FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(
                    '${filtered.length} wilayah',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Wilayah tidak ditemukan',
                          style: TextStyle(color: Colors.blueGrey[400]),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey[100]),
                        itemBuilder: (context, index) {
                          final w = filtered[index];
                          return ListTile(
                            leading: const Icon(Icons.map_outlined,
                                color: Color(0xFF0F4C81)),
                            title: Text(
                              w.label,
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () => Navigator.pop(context, w),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
