import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/documentation_upload_service.dart';

const List<_DocumentationCategoryOption> _categoryOptions = [
  _DocumentationCategoryOption(
    'koordinasi',
    'Koordinasi',
    Icons.groups_rounded,
  ),
  _DocumentationCategoryOption(
    'pendataan',
    'Pendataan',
    Icons.edit_note_rounded,
  ),
  _DocumentationCategoryOption(
    'pengawasan',
    'Pengawasan',
    Icons.verified_user_rounded,
  ),
  _DocumentationCategoryOption(
    'pertemuan',
    'Pertemuan',
    Icons.handshake_rounded,
  ),
  _DocumentationCategoryOption('lainnya', 'Lainnya', Icons.category_rounded),
  _DocumentationCategoryOption(
    'bukti paket data',
    'Bukti Paket Data',
    Icons.receipt_long_rounded,
  ),
];

class DokumentasiPage extends StatefulWidget {
  const DokumentasiPage({super.key});

  @override
  State<DokumentasiPage> createState() => _DokumentasiPageState();
}

class _DokumentasiPageState extends State<DokumentasiPage> {
  final DocumentationUploadService _service = DocumentationUploadService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String _query = '';
  List<DocumentationEntry> _entries = [];

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
    });

    try {
      final entries = await _service.loadEntries();
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteLocalEntry(DocumentationEntry entry) async {
    await _service.deleteLocalEntry(entry);
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
  }

  List<DocumentationEntry> get _filteredEntries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((entry) {
      final haystack = [
        entry.fileName,
        entry.category,
        entry.description,
        entry.uploadedAt,
        entry.driveFileId,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;

    return Container(
      color: const Color(0xFFF3F6FB),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          onPressed: _showUploadDialog,
          backgroundColor: const Color(0xFF1D8F5A),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeroSection()),
                      SliverToBoxAdapter(child: _buildSearchSection()),
                      SliverToBoxAdapter(
                        child: _buildSectionHeader(resultCount: entries.length),
                      ),
                      if (entries.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverList.separated(
                            itemCount: entries.length,
                            itemBuilder: (context, index) =>
                                _buildEntryTile(entries[index], index),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Dokumentasi',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10243E),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPreview(File? selectedFile) {
    if (selectedFile == null) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.1),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 44, color: Color(0xFF2D77D0)),
            SizedBox(height: 10),
            Text(
              'Belum ada gambar dipilih',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.file(
        selectedFile,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildCategoryCard({
    required _DocumentationCategoryOption option,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAF3FF) : const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2D77D0)
                : const Color(0xFF2D77D0).withValues(alpha: 0.10),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2D77D0) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                option.icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF2D77D0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF143A70)
                      : const Color(0xFF314760),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<_PickedDocumentationFile?> _pickImage(ImageSource source) async {
    if (source == ImageSource.gallery && _usesDesktopFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) return null;
      return _PickedDocumentationFile(
        file: File(path),
        originalName: result?.files.single.name,
      );
    }

    if (source == ImageSource.camera && _usesDesktopFilePicker) {
      throw Exception('Kamera belum didukung di macOS. Gunakan Galeri.');
    }

    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (image == null) return null;

    return _PickedDocumentationFile(
      file: File(image.path),
      originalName: image.name,
    );
  }

  Future<void> _showUploadDialog() async {
    File? selectedFile;
    String? selectedOriginalName;
    String? selectedCategory;
    String? dialogError;
    bool isUploading = false;
    final descriptionController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: !isUploading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> handlePick(ImageSource source) async {
              try {
                final picked = await _pickImage(source);
                if (picked == null) return;
                setDialogState(() {
                  selectedFile = picked.file;
                  selectedOriginalName = picked.originalName;
                  dialogError = null;
                });
              } catch (e) {
                setDialogState(() {
                  dialogError = 'Gagal memilih gambar: $e';
                });
              }
            }

            Future<void> handleUpload() async {
              final file = selectedFile;
              final category = selectedCategory;
              if (file == null || category == null) return;

              setDialogState(() {
                isUploading = true;
                dialogError = null;
              });

              try {
                final entry = await _service.uploadDocumentation(
                  file,
                  originalName: selectedOriginalName,
                  category: category,
                  description: descriptionController.text,
                );
                if (!mounted) return;

                setState(() {
                  _entries.insert(0, entry);
                });

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Upload dokumentasi berhasil'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                setDialogState(() {
                  isUploading = false;
                  dialogError = e.toString();
                });
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Upload Dokumentasi',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10243E),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: isUploading
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSelectedPreview(selectedFile),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isUploading
                                  ? null
                                  : () => handlePick(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Galeri'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isUploading
                                  ? null
                                  : () => handlePick(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Kamera'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Pilih Kategori',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _categoryOptions
                            .map(
                              (option) => _buildCategoryCard(
                                option: option,
                                isSelected: selectedCategory == option.value,
                                onTap: isUploading
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          selectedCategory = option.value;
                                        });
                                      },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        textInputAction: TextInputAction.done,
                        enabled: !isUploading,
                        decoration: InputDecoration(
                          labelText: 'Keterangan',
                          hintText: 'Tambahkan catatan jika diperlukan',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: const Color(0xFFF7FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF2D77D0,
                              ).withValues(alpha: 0.12),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF2D77D0,
                              ).withValues(alpha: 0.12),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D77D0),
                            ),
                          ),
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              isUploading ||
                                  selectedFile == null ||
                                  selectedCategory == null
                              ? null
                              : handleUpload,
                          icon: isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: Text(isUploading ? 'Upload...' : 'Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D8F5A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    descriptionController.dispose();
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
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
            hintText: 'Cari nama file dokumentasi',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? IconButton(
                    onPressed: _loadData,
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
                  'Riwayat Upload',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$resultCount file tampil',
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
            child: const Text(
              'Lokal perangkat',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF144A8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(DocumentationEntry entry, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _showEntryDetail(entry, index),
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
                _buildEntryThumbnail(entry, index),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10243E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Diupload ${_formatDateTime(entry.uploadedAt)}',
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
                          if (entry.category.isNotEmpty)
                            _buildMiniBadge(
                              icon: Icons.sell_outlined,
                              label: _formatCategoryLabel(entry.category),
                            ),
                          _buildMiniBadge(
                            icon: Icons.folder_outlined,
                            label: _formatBytes(entry.fileSize),
                          ),
                          _buildMiniBadge(
                            icon: Icons.cloud_done_outlined,
                            label: 'Drive tersimpan',
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

  Widget _buildEntryThumbnail(DocumentationEntry entry, int index) {
    final file = File(entry.localPath);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(file, width: 72, height: 72, fit: BoxFit.cover),
      );
    }

    return Container(
      width: 72,
      height: 72,
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
                Icons.add_a_photo_outlined,
                size: 38,
                color: Color(0xFF2D77D0),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Belum ada dokumentasi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Pilih gambar dari galeri atau kamera, lalu upload ke Google Drive.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
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
              'Gagal memuat dokumentasi',
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
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetail(DocumentationEntry entry, int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final file = File(entry.localPath);
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
                              entry.fileName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload #${index + 1} pada ${_formatDateTime(entry.uploadedAt)}',
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
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      if (file.existsSync())
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.file(file, fit: BoxFit.cover),
                        ),
                      const SizedBox(height: 14),
                      _buildDetailPanel(
                        icon: Icons.description_outlined,
                        title: 'Informasi File',
                        content: [
                          'Nama file: ${entry.fileName}',
                          'Kategori: ${_formatCategoryLabel(entry.category)}',
                          if (entry.description.trim().isNotEmpty)
                            'Keterangan: ${entry.description.trim()}',
                          'Ukuran: ${_formatBytes(entry.fileSize)}',
                          'Waktu upload: ${_formatDateTime(entry.uploadedAt)}',
                          'Drive file ID: ${entry.driveFileId}',
                        ].join('\n'),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _openUrl(entry.driveViewUrl),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Buka Drive'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await _deleteLocalEntry(entry);
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Hapus Lokal'),
                          ),
                        ],
                      ),
                    ],
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
            content,
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

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatDateTime(String isoValue) {
    final dateTime = DateTime.tryParse(isoValue)?.toLocal();
    if (dateTime == null) return isoValue;
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatCategoryLabel(String value) {
    for (final option in _categoryOptions) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  bool get _usesDesktopFilePicker {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }
}

class _DocumentationCategoryOption {
  final String value;
  final String label;
  final IconData icon;

  const _DocumentationCategoryOption(this.value, this.label, this.icon);
}

class _PickedDocumentationFile {
  final File file;
  final String? originalName;

  const _PickedDocumentationFile({required this.file, this.originalName});
}
