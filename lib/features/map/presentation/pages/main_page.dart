import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'map_page.dart';
import 'saved_page.dart';
import 'contribution_page.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/place.dart';
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
  List<Place> _allPlaces = [];

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

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _searchResults = _allPlaces
          .where(
            (place) =>
                place.name.toLowerCase().contains(query.toLowerCase()) ||
                place.description.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
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
                child: _searchResults.isEmpty
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
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                            ),
                            title: Text(place.name),
                            subtitle: Text(place.description),
                            onTap: () {
                              // Close bottom sheet and navigate to location
                              Navigator.pop(context);
                              _sharedMapController.move(place.position, 15.0);
                              // Switch to map tab if not already there
                              if (_selectedIndex != 0) {
                                setState(() {
                                  _selectedIndex = 0;
                                });
                              }
                              // Clear search and unfocus
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                            },
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

  Widget _buildOverlayContent() {
    switch (_selectedIndex) {
      case 0:
        return MapPage(mapController: _sharedMapController);
      case 1:
        return SavedPage(mapController: _sharedMapController);
      case 2:
        return ContributionPage(mapController: _sharedMapController);
      default:
        return MapPage(mapController: _sharedMapController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          MapBloc(
              getInitialMapConfig: GetInitialMapConfig(MapRepositoryImpl()),
              getPlaces: GetPlaces(MapRepositoryImpl()),
              getFirstPolygonMeta: GetFirstPolygonMetaFromGeoJson(
                MapRepositoryImpl(),
              ),
              getAllPolygonsMeta: GetAllPolygonsMetaFromGeoJson(
                MapRepositoryImpl(),
              ),
            )
            ..add(const MapInitRequested())
            ..add(const PlacesRequested())
            ..add(const PolygonRequested())
            ..add(const PolygonsListRequested()),
      child: Scaffold(
        body: Stack(
          children: [
            // Base map layer - always MapPage to maintain consistent map
            MapPage(mapController: _sharedMapController),
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
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: 'Jelajah',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark),
              label: 'Disimpan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline),
              label: 'Kontribusi',
            ),
          ],
        ),
      ),
    );
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