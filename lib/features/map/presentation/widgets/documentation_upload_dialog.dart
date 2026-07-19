import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  _DocumentationCategoryOption(
    'fasih',
    'Fasih',
    Icons.fact_check_rounded,
  ),
  _DocumentationCategoryOption('lainnya', 'Lainnya', Icons.category_rounded),
  _DocumentationCategoryOption(
    'bukti paket data',
    'Bukti Paket Data',
    Icons.receipt_long_rounded,
  ),
];

Future<DocumentationEntry?> showDocumentationUploadDialog(
  BuildContext context, {
  DocumentationUploadService? service,
}) {
  return showDialog<DocumentationEntry>(
    context: context,
    builder: (dialogContext) => _DocumentationUploadDialog(
      service: service ?? DocumentationUploadService(),
    ),
  );
}

class _DocumentationUploadDialog extends StatefulWidget {
  final DocumentationUploadService service;

  const _DocumentationUploadDialog({required this.service});

  @override
  State<_DocumentationUploadDialog> createState() =>
      _DocumentationUploadDialogState();
}

class _DocumentationUploadDialogState
    extends State<_DocumentationUploadDialog> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descriptionController = TextEditingController();

  File? _selectedFile;
  String? _selectedOriginalName;
  String? _selectedCategory;
  String? _dialogError;
  bool _isUploading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isUploading,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
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
                      onPressed: _isUploading
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSelectedPreview(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading
                            ? null
                            : () => _handlePick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeri'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading
                            ? null
                            : () => _handlePick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Kamera'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Pilih Kategori',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categoryOptions
                      .map(
                        (option) => _buildCategoryCard(
                          option: option,
                          isSelected: _selectedCategory == option.value,
                          onTap: _isUploading
                              ? null
                              : () {
                                  setState(() {
                                    _selectedCategory = option.value;
                                  });
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  enabled: !_isUploading,
                  decoration: InputDecoration(
                    labelText: 'Keterangan',
                    hintText: 'Tambahkan catatan jika diperlukan',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFFF7FAFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: const Color(0xFF2D77D0).withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: const Color(0xFF2D77D0).withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF2D77D0)),
                    ),
                  ),
                ),
                if (_dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _dialogError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isUploading ||
                            _selectedFile == null ||
                            _selectedCategory == null
                        ? null
                        : _handleUpload,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_isUploading ? 'Upload...' : 'Upload'),
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
      ),
    );
  }

  Widget _buildSelectedPreview() {
    if (_selectedFile == null) {
      return Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.1),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 34, color: Color(0xFF2D77D0)),
            SizedBox(height: 8),
            Text(
              'Belum ada gambar dipilih',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.file(
        _selectedFile!,
        height: 150,
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAF3FF) : const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2D77D0)
                : const Color(0xFF2D77D0).withValues(alpha: 0.10),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              option.icon,
              size: 17,
              color: isSelected
                  ? const Color(0xFF2D77D0)
                  : const Color(0xFF3D6B9D),
            ),
            const SizedBox(width: 6),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? const Color(0xFF143A70)
                    : const Color(0xFF314760),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePick(ImageSource source) async {
    try {
      final picked = await _pickImage(source);
      if (picked == null || !mounted) return;
      setState(() {
        _selectedFile = picked.file;
        _selectedOriginalName = picked.originalName;
        _dialogError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dialogError = 'Gagal memilih gambar: $e';
      });
    }
  }

  Future<void> _handleUpload() async {
    final file = _selectedFile;
    final category = _selectedCategory;
    if (file == null || category == null) return;

    setState(() {
      _isUploading = true;
      _dialogError = null;
    });

    try {
      final entry = await widget.service.uploadDocumentation(
        file,
        originalName: _selectedOriginalName,
        category: category,
        description: _descriptionController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _dialogError = e.toString();
      });
    }
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
