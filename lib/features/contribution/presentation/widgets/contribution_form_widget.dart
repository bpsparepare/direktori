import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';

/// Widget form untuk menambah kontribusi baru
class ContributionFormWidget extends StatefulWidget {
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;
  final String? initialActionType;

  const ContributionFormWidget({
    super.key,
    this.onSuccess,
    this.onCancel,
    this.initialActionType,
  });

  @override
  State<ContributionFormWidget> createState() => _ContributionFormWidgetState();
}

class _ContributionFormWidgetState extends State<ContributionFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _targetIdController = TextEditingController();
  final _changesController = TextEditingController();

  String _selectedActionType = 'create';
  String _selectedTargetType = 'direktori';
  Position? _currentPosition;
  bool _isLoadingLocation = false;

  final List<Map<String, String>> _actionTypes = [
    {'value': 'create', 'label': 'Menambah'},
    {'value': 'update', 'label': 'Memperbarui'},
    {'value': 'delete', 'label': 'Menghapus'},
    {'value': 'verify', 'label': 'Memverifikasi'},
  ];

  final List<Map<String, String>> _targetTypes = [
    {'value': 'direktori', 'label': 'Direktori'},
    {'value': 'location', 'label': 'Lokasi'},
    {'value': 'business', 'label': 'Bisnis'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialActionType != null) {
      _selectedActionType = widget.initialActionType!;
    }
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _targetIdController.dispose();
    _changesController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Layanan lokasi tidak aktif');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Izin lokasi ditolak');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Izin lokasi ditolak secara permanen');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mendapatkan lokasi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lokasi belum tersedia. Silakan tunggu atau coba lagi.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final changes = _changesController.text.trim().isNotEmpty
        ? {'description': _changesController.text.trim()}
        : null;

    context.read<ContributionBloc>().add(
      CreateContributionEvent(
        actionType: _selectedActionType,
        targetType: _selectedTargetType,
        targetId: _targetIdController.text.trim(),
        changes: changes,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ContributionBloc, ContributionState>(
      listener: (context, state) {
        if (state is ContributionCreated) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kontribusi berhasil ditambahkan!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onSuccess?.call();
        } else if (state is ContributionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menambah kontribusi: ${state.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tambah Kontribusi',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action Type
              Text(
                'Jenis Aksi',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedActionType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: _actionTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['value'],
                    child: Text(type['label']!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedActionType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Target Type
              Text(
                'Jenis Target',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedTargetType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: _targetTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['value'],
                    child: Text(type['label']!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedTargetType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Target ID
              Text(
                'ID Target',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetIdController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Masukkan ID target (contoh: direktori_123)',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'ID target harus diisi';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Changes/Description
              Text(
                'Deskripsi Perubahan (Opsional)',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _changesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Jelaskan perubahan yang dilakukan...',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Location Status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: _currentPosition != null
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lokasi',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _isLoadingLocation
                                ? 'Mendapatkan lokasi...'
                                : _currentPosition != null
                                ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
                                : 'Lokasi tidak tersedia',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoadingLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_currentPosition == null)
                      IconButton(
                        onPressed: _getCurrentLocation,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Coba lagi',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button
              BlocBuilder<ContributionBloc, ContributionState>(
                builder: (context, state) {
                  final isLoading =
                      state is ContributionLoading ||
                      (state is ContributionLoaded &&
                          state.isCreatingContribution);

                  return ElevatedButton(
                    onPressed: isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Menyimpan...'),
                            ],
                          )
                        : const Text(
                            'Tambah Kontribusi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
