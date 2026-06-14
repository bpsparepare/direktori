import 'package:flutter/material.dart';
import '../../data/services/groundcheck_supabase_service.dart';

class WilayahTugasPage extends StatefulWidget {
  const WilayahTugasPage({super.key});

  @override
  State<WilayahTugasPage> createState() => _WilayahTugasPageState();
}

class _WilayahTugasPageState extends State<WilayahTugasPage> {
  final GroundcheckSupabaseService _service = GroundcheckSupabaseService();
  final TextEditingController _searchController = TextEditingController();

  static const String _allKabupaten = 'Semua';

  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  String _query = '';
  String _selectedKabupaten = _allKabupaten;
  Se2026UserProfile? _profile;
  List<Map<String, dynamic>> _wilayah = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final profile = await _service.fetchCurrentSe2026Profile();
      final wilayah = await _service.fetchCurrentUserWilayahTugas();
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _wilayah = wilayah;
        _isLoading = false;
        _statusMessage = 'Menampilkan daftar wilayah kerja sesuai penugasan.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    try {
      final profile = await _service.fetchCurrentSe2026Profile();
      final wilayah = await _service.fetchCurrentUserWilayahTugas();
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _wilayah = wilayah;
        _error = null;
        _isLoading = false;
        _statusMessage = 'Daftar wilayah kerja diperbarui.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<String> get _kabupatenOptions {
    final values =
        _wilayah
            .map((item) => _text(item['nm_kab']))
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [_allKabupaten, ...values];
  }

  List<_WilayahItemData> get _filteredItems {
    final query = _query.trim().toLowerCase();

    final items = _wilayah.map((item) => _WilayahItemData.fromMap(item)).where((
      item,
    ) {
      if (_selectedKabupaten != _allKabupaten &&
          item.kabupaten != _selectedKabupaten) {
        return false;
      }

      final haystack = [
        item.id,
        item.provinsi,
        item.kabupaten,
        item.kecamatan,
        item.desa,
        item.sls,
        item.kodeProv,
        item.kodeKab,
        item.kodeKec,
        item.kodeDesa,
        item.kodeSls,
        item.kodeSubsls,
      ].join(' ').toLowerCase();

      if (query.isNotEmpty && !haystack.contains(query)) {
        return false;
      }
      return true;
    }).toList();

    items.sort((a, b) {
      final kabCompare = a.kabupaten.compareTo(b.kabupaten);
      if (kabCompare != 0) return kabCompare;
      final kecCompare = a.kecamatan.compareTo(b.kecamatan);
      if (kecCompare != 0) return kecCompare;
      final desaCompare = a.desa.compareTo(b.desa);
      if (desaCompare != 0) return desaCompare;
      return a.id.compareTo(b.id);
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return Container(
      color: const Color(0xFFF3F6FB),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeroSection()),
                      SliverToBoxAdapter(child: _buildSearchSection()),
                      SliverToBoxAdapter(
                        child: _buildSectionHeader(resultCount: items.length),
                      ),
                      if (_profile == null || _profile?.isActive != true)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildProfileMissingState(),
                        )
                      else if (items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverList.separated(
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                _buildWilayahTile(items[index], index),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final roleLabel = (_profile?.role ?? '-').toUpperCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0), Color(0xFF7AB6FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.map_outlined, color: Colors.white),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Text(
                  'Wilayah Kerja',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Daftar penugasan wilayah untuk role $roleLabel.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroBadge(
                icon: Icons.badge_outlined,
                label: 'Role $roleLabel',
              ),
              _buildHeroBadge(
                icon: Icons.assignment_outlined,
                label: '${_wilayah.length} penugasan',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Cari desa, kecamatan, kabupaten, atau kode wilayah',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? IconButton(
                        onPressed: _refreshData,
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kabupatenOptions.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final kabupaten = _kabupatenOptions[index];
                final isSelected = kabupaten == _selectedKabupaten;
                return FilterChip(
                  label: Text(kabupaten),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedKabupaten = kabupaten;
                    });
                  },
                  showCheckmark: false,
                  selectedColor: const Color(
                    0xFF2D77D0,
                  ).withValues(alpha: 0.14),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF2D77D0)
                        : Colors.grey.withValues(alpha: 0.24),
                  ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF144A8B)
                        : const Color(0xFF526070),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                );
              },
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required int resultCount}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Wilayah',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$resultCount hasil tampil',
                  style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
            ),
            child: Text(
              _selectedKabupaten == _allKabupaten
                  ? 'Semua kabupaten'
                  : _selectedKabupaten,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF144A8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWilayahTile(_WilayahItemData item, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _showWilayahDetail(item, index),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF2D77D0).withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF103C76), Color(0xFF2F83DB)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10243E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.previewText,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: Colors.blueGrey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMiniBadge(
                            icon: Icons.apartment_rounded,
                            label: item.kabupaten.isEmpty
                                ? 'Kabupaten -'
                                : item.kabupaten,
                          ),
                          _buildMiniBadge(
                            icon: Icons.account_tree_outlined,
                            label: item.sls.isEmpty
                                ? 'SLS belum ada'
                                : item.sls,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF2D77D0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF3D6B9D)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D5066),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                size: 38,
                color: Color(0xFF2D77D0),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Wilayah tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ganti kata kunci pencarian atau ubah filter kabupaten.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedKabupaten = _allKabupaten;
                });
              },
              child: const Text('Reset Filter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileMissingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 52, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Profil petugas tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Akun ini belum terhubung ke data petugas SE2026 atau statusnya tidak aktif.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Muat Ulang'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat wilayah kerja',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWilayahDetail(_WilayahItemData item, int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final maxWidth = size.width > 760 ? 720.0 : size.width - 24;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: size.height * 0.82,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 12, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF143A70), Color(0xFF2D77D0)],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Detail penugasan wilayah #${index + 1}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _buildDetailPanel(
                          icon: Icons.place_outlined,
                          title: 'Nama Wilayah',
                          content: [
                            if (item.provinsi.isNotEmpty)
                              'Provinsi: ${item.provinsi}',
                            if (item.kabupaten.isNotEmpty)
                              'Kabupaten: ${item.kabupaten}',
                            if (item.kecamatan.isNotEmpty)
                              'Kecamatan: ${item.kecamatan}',
                            if (item.desa.isNotEmpty) 'Desa: ${item.desa}',
                            if (item.sls.isNotEmpty) 'SLS: ${item.sls}',
                          ].join('\n'),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailPanel(
                          icon: Icons.pin_outlined,
                          title: 'Kode Wilayah',
                          content: [
                            'Kode Provinsi: ${item.kodeProvOrDash}',
                            'Kode Kabupaten: ${item.kodeKabOrDash}',
                            'Kode Kecamatan: ${item.kodeKecOrDash}',
                            'Kode Desa: ${item.kodeDesaOrDash}',
                            'Kode SLS: ${item.kodeSlsOrDash}',
                            'Kode SubSLS: ${item.kodeSubslsOrDash}',
                          ].join('\n'),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailPanel(
                          icon: Icons.assignment_ind_outlined,
                          title: 'Referensi Tugas',
                          content: [
                            'ID Tugas: ${item.idOrDash}',
                            'ID SLS: ${item.idSlsOrDash}',
                          ].join('\n'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2D77D0)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162F4D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content.isEmpty ? '-' : content,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.blueGrey[700],
            ),
          ),
        ],
      ),
    );
  }

  String _text(dynamic value) => value?.toString() ?? '';
}

class _WilayahItemData {
  final String id;
  final String idSls;
  final String provinsi;
  final String kabupaten;
  final String kecamatan;
  final String desa;
  final String sls;
  final String kodeProv;
  final String kodeKab;
  final String kodeKec;
  final String kodeDesa;
  final String kodeSls;
  final String kodeSubsls;

  const _WilayahItemData({
    required this.id,
    required this.idSls,
    required this.provinsi,
    required this.kabupaten,
    required this.kecamatan,
    required this.desa,
    required this.sls,
    required this.kodeProv,
    required this.kodeKab,
    required this.kodeKec,
    required this.kodeDesa,
    required this.kodeSls,
    required this.kodeSubsls,
  });

  factory _WilayahItemData.fromMap(Map<String, dynamic> map) {
    return _WilayahItemData(
      id: map['id']?.toString() ?? '',
      idSls: map['id_sls']?.toString() ?? '',
      provinsi: map['nm_prov']?.toString() ?? '',
      kabupaten: map['nm_kab']?.toString() ?? '',
      kecamatan: map['nm_kec']?.toString() ?? '',
      desa: map['nm_desa']?.toString() ?? '',
      sls: map['nm_sls']?.toString() ?? '',
      kodeProv: map['kode_prov']?.toString() ?? '',
      kodeKab: map['kode_kab']?.toString() ?? '',
      kodeKec: map['kode_kec']?.toString() ?? '',
      kodeDesa: map['kode_desa']?.toString() ?? '',
      kodeSls: map['kode_sls']?.toString() ?? '',
      kodeSubsls: map['kode_subsls']?.toString() ?? '',
    );
  }

  String get title {
    final parts = [
      desa,
      kecamatan,
      kabupaten,
    ].where((value) => value.isNotEmpty).toList();
    return parts.isEmpty
        ? (id.isEmpty ? 'Wilayah Tugas' : id)
        : parts.join(' - ');
  }

  String get previewText {
    final lines = <String>[];
    if (provinsi.isNotEmpty) lines.add('Provinsi $provinsi');
    if (sls.isNotEmpty) lines.add('SLS $sls');
    if (kodeDesa.isNotEmpty) lines.add('Kode desa $kodeDesa');
    return lines.isEmpty
        ? 'Pilih untuk melihat detail wilayah tugas.'
        : lines.join(' • ');
  }

  String get idOrDash => id.isEmpty ? '-' : id;
  String get idSlsOrDash => idSls.isEmpty ? '-' : idSls;
  String get kodeProvOrDash => kodeProv.isEmpty ? '-' : kodeProv;
  String get kodeKabOrDash => kodeKab.isEmpty ? '-' : kodeKab;
  String get kodeKecOrDash => kodeKec.isEmpty ? '-' : kodeKec;
  String get kodeDesaOrDash => kodeDesa.isEmpty ? '-' : kodeDesa;
  String get kodeSlsOrDash => kodeSls.isEmpty ? '-' : kodeSls;
  String get kodeSubslsOrDash => kodeSubsls.isEmpty ? '-' : kodeSubsls;
}
