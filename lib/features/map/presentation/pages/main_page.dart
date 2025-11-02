import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'map_page.dart';
import 'saved_page.dart';
import 'contribution_page.dart';
import '../../../direktori/presentation/pages/direktori_list_page.dart';
import '../../../direktori/presentation/bloc/direktori_bloc.dart';
import '../../../direktori/domain/usecases/get_direktori_list.dart';
import '../../../direktori/data/repositories/direktori_repository_impl.dart';
import '../../../direktori/data/datasources/direktori_remote_datasource.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/place.dart';
import '../../data/models/direktori_model.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  late MapController _sharedMapController; // Add shared MapController
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Place> _searchResults = [];
  List<DirektoriModel> _directoryResults = [];
  List<Place> _allPlaces = [];
  DirektoriModel?
  _pendingCoordinateDirectory; // Directory selected to add coordinates

  @override
  void initState() {
    super.initState();
    _sharedMapController = MapController();
    _loadPlaces();
  }

  void _loadPlaces() async {
    // Load dummy places from repository
    final repository = MapRepositoryImpl();
    _allPlaces = await repository.getPlaces();
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _directoryResults = [];
      });
      return;
    }

    // Search places with coordinates
    final placesWithCoordinates = _allPlaces
        .where(
          (place) =>
              place.name.toLowerCase().contains(query.toLowerCase()) ||
              place.description.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();

    // Search directories without coordinates
    List<DirektoriModel> directoriesWithoutCoordinates = [];
    try {
      final repository = MapRepositoryImpl();
      directoriesWithoutCoordinates = await repository
          .searchDirectoriesWithoutCoordinates(query);
    } catch (e) {
      print('Error searching directories without coordinates: $e');
    }

    setState(() {
      _searchResults = placesWithCoordinates;
      _directoryResults = directoriesWithoutCoordinates;
    });

    // Show bottom sheet with results
    _showSearchResults();
  }

  void _showSearchResults() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Hasil pencarian untuk "${_searchController.text}"',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Search results
              Expanded(
                child: (_searchResults.isEmpty && _directoryResults.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tidak ada hasil ditemukan',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount:
                            _searchResults.length + _directoryResults.length,
                        itemBuilder: (context, index) {
                          // Show places with coordinates first
                          if (index < _searchResults.length) {
                            final place = _searchResults[index];
                            return ListTile(
                              leading: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                              ),
                              title: Text(place.name),
                              subtitle: Text(place.description),
                              trailing: const Icon(
                                Icons.map,
                                color: Colors.green,
                                size: 16,
                              ),
                              onTap: () {
                                // Close bottom sheet and navigate to location
                                Navigator.pop(context);
                                _sharedMapController.move(place.position, 18.0);
                                // Switch to map tab if not already there
                                if (_selectedIndex != 0) {
                                  setState(() {
                                    _selectedIndex = 0;
                                  });
                                }
                                // Clear search and unfocus
                                _searchController.clear();
                                _searchFocusNode.unfocus();
                                // Add place selection to MapBloc for visual indicator
                                context.read<MapBloc>().add(
                                  PlaceSelected(place),
                                );
                              },
                            );
                          } else {
                            // Show directories without coordinates
                            final directoryIndex =
                                index - _searchResults.length;
                            final directory = _directoryResults[directoryIndex];
                            return ListTile(
                              leading: const Icon(
                                Icons.business,
                                color: Colors.orange,
                              ),
                              title: Text(directory.namaUsaha),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (directory.alamat != null)
                                    Text(
                                      directory.alamat!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  Text(
                                    'Status: ${_getKeberadaanUsahaDescription(directory.keberadaanUsaha)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: directory.keberadaanUsaha == 1
                                          ? Colors.green
                                          : directory.keberadaanUsaha == 4
                                          ? Colors.red
                                          : Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'ID SLS: ${directory.idSls} • Tanpa koordinat',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.location_off,
                                color: Colors.grey,
                                size: 16,
                              ),
                              onTap: () {
                                // Close bottom sheet
                                Navigator.pop(context);
                                // Switch to map tab and enable Add Coordinate mode
                                setState(() {
                                  _selectedIndex = 0;
                                  _pendingCoordinateDirectory = directory;
                                });
                                // Inform user how to use the mode
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Geser peta untuk menentukan posisi pusat, lalu tekan Simpan.',
                                    ),
                                    backgroundColor: Colors.blue,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                                // Clear search and unfocus
                                _searchController.clear();
                                _searchFocusNode.unfocus();
                              },
                            );
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent() {
    switch (_selectedIndex) {
      case 0:
        return MapPage(mapController: _sharedMapController);
      case 1:
        return SavedPage(mapController: _sharedMapController);
      case 2:
        return ContributionPage(mapController: _sharedMapController);
      case 3:
        return DirektoriListPage();
      default:
        return MapPage(mapController: _sharedMapController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Base map layer - always MapPage to maintain consistent map
          MapPage(
            mapController: _sharedMapController,
            coordinateTarget: _pendingCoordinateDirectory,
            onExitCoordinateMode: () {
              setState(() {
                _pendingCoordinateDirectory = null;
              });
            },
          ),
          // Overlay content based on selected tab
          if (_selectedIndex != 0) _buildOverlayContent(),
          // Floating search bar with avatar (Google Maps style)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Search TextField
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Cari tempat...',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey,
                            size: 24,
                          ),
                        ),
                        style: const TextStyle(fontSize: 16),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            _performSearch(value.trim());
                          }
                        },
                        onChanged: (value) {
                          // Clear place selection when user starts typing
                          context.read<MapBloc>().add(const PlaceCleared());
                        },
                      ),
                    ),
                  ),
                  // Avatar with popup menu
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PopupMenuButton<String>(
                      icon: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_circle,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      onSelected: (value) {
                        if (value == 'logout') {
                          _showLogoutDialog(context);
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Logout'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          // Clear place selection when switching tabs
          context.read<MapBloc>().add(const PlaceCleared());
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Jelajah'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark),
            label: 'Disimpan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Kontribusi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business),
            label: 'Direktori',
          ),
        ],
      ),
    );
  }

  // Helper function to get keberadaan usaha description
  String _getKeberadaanUsahaDescription(int? keberadaanUsaha) {
    if (keberadaanUsaha == null) {
      return 'Undefined';
    }

    switch (keberadaanUsaha) {
      case 1:
        return 'Aktif';
      case 2:
        return 'Tutup Sementara';
      case 3:
        return 'Belum Beroperasi/Berproduksi';
      case 4:
        return 'Tutup';
      case 5:
        return 'Alih Usaha';
      case 6:
        return 'Tidak Ditemukan';
      case 7:
        return 'Aktif Pindah';
      case 8:
        return 'Aktif Nonrespon';
      case 9:
        return 'Duplikat';
      case 10:
        return 'Salah Kode Wilayah';
      default:
        return 'Tidak Diketahui';
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Apakah Anda yakin ingin logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AuthBloc>().add(AuthSignOutRequested());
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
