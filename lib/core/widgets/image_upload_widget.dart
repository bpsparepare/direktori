import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_service_locator.dart';
import '../services/image_upload_service.dart';

class ImageUploadWidget extends StatefulWidget {
  final Function(String imageUrl) onImageUploaded;
  final String? initialImageUrl;
  final String? hintText;
  final double? height;
  final double? width;

  const ImageUploadWidget({
    super.key,
    required this.onImageUploaded,
    this.initialImageUrl,
    this.hintText,
    this.height,
    this.width,
  });

  @override
  State<ImageUploadWidget> createState() => _ImageUploadWidgetState();
}

class _ImageUploadWidgetState extends State<ImageUploadWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _urlController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _currentImageUrl;
  bool _isUploading = false;
  String? _uploadError;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentImageUrl = widget.initialImageUrl;
    if (_currentImageUrl != null) {
      _urlController.text = _currentImageUrl!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    print('🔄 Starting image picker...');
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        print('✅ Image selected: ${image.path}');
        print(
          '📄 Image details - Name: ${image.name}, Size: ${await image.length()} bytes',
        );
        setState(() {
          _selectedFile = File(image.path);
          _uploadError = null;
        });
      } else {
        print('ℹ️ No image selected by user');
      }
    } catch (e) {
      print('❌ Failed to pick image: $e');
      setState(() {
        _uploadError = 'Gagal memilih gambar: ${e.toString()}';
      });
    }
  }

  Future<void> _pickImageFromCamera() async {
    print('🔄 Starting camera capture...');
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        print('✅ Image captured: ${image.path}');
        setState(() {
          _selectedFile = File(image.path);
          _uploadError = null;
        });
      } else {
        print('ℹ️ Camera capture cancelled by user');
      }
    } catch (e) {
      print('❌ Failed to capture image: $e');
      setState(() {
        _uploadError = 'Gagal mengambil gambar dari kamera: ${e.toString()}';
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedFile == null) {
      print('❌ No file selected for upload');
      return;
    }

    print('🔄 Starting image upload process...');
    print('📄 File to upload: ${_selectedFile!.path}');

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      print('🔄 Checking if ImageServiceLocator is initialized...');
      if (!ImageServiceLocator.isInitialized) {
        print('❌ ImageServiceLocator not initialized');
        throw Exception('Image upload service belum diinisialisasi');
      }
      print('✅ ImageServiceLocator is initialized');

      print('🔄 Getting service instance...');
      final service = ImageServiceLocator.instance;
      print('✅ Service instance obtained: ${service.serviceName}');

      print('🔄 Calling service.uploadImage...');
      final imageUrl = await service.uploadImage(_selectedFile!);
      print('✅ Upload successful! URL: $imageUrl');

      setState(() {
        _currentImageUrl = imageUrl;
        _urlController.text = imageUrl;
        _isUploading = false;
      });

      widget.onImageUploaded(imageUrl);

      // Show success message
      if (mounted) {
        print('✅ Showing success message to user');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gambar berhasil diupload!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Upload failed with error: $e');
      print('   Error Type: ${e.runtimeType}');
      print('   Stack Trace: ${StackTrace.current}');

      setState(() {
        _isUploading = false;
        _uploadError = 'Gagal upload gambar: ${e.toString()}';
      });
    }
  }

  void _validateAndSetUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Basic URL validation
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath) {
      setState(() {
        _uploadError = 'URL tidak valid';
      });
      return;
    }

    setState(() {
      _currentImageUrl = url;
      _uploadError = null;
    });

    widget.onImageUploaded(url);
  }

  Widget _buildImagePreview() {
    if (_currentImageUrl != null) {
      return Container(
        height: widget.height ?? 200,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            _currentImageUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade100,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    SizedBox(height: 8),
                    Text('Gagal memuat gambar'),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    if (_selectedFile != null) {
      return Container(
        height: widget.height ?? 200,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(_selectedFile!, fit: BoxFit.cover),
        ),
      );
    }

    return Container(
      height: widget.height ?? 200,
      width: widget.width ?? double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
          style: BorderStyle.solid,
        ),
        color: Colors.grey.shade50,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            widget.hintText ?? 'Pilih gambar atau masukkan URL',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image preview
        _buildImagePreview(),

        const SizedBox(height: 16),

        // Tab bar
        TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Upload File'),
            Tab(text: 'URL Gambar'),
          ],
        ),

        const SizedBox(height: 16),

        // Tab content
        SizedBox(
          height: 120,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Upload tab
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUploading ? null : _pickImage,
                          icon: const Icon(Icons.photo_library),
                          label: Text(
                            _selectedFile == null
                                ? 'Pilih Gambar'
                                : 'Ganti Gambar',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUploading ? null : _pickImageFromCamera,
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Ambil dari Kamera'),
                        ),
                      ),
                      if (_selectedFile != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _uploadImage,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedFile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'File: ${_selectedFile!.path.split('/').last}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),

              // URL tab
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL Gambar',
                      hintText: 'https://example.com/image.jpg',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _validateAndSetUrl(),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _validateAndSetUrl,
                    icon: const Icon(Icons.check),
                    label: const Text('Gunakan URL'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Error message
        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _uploadError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
