import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'groundcheck_history_page.dart';
import 'map_page.dart';
import 'saved_page.dart';
import 'groundcheck_page.dart';
import '../../../contribution/presentation/pages/contribution_page.dart';
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
  final int? initialTabIndex;
  const MainPage({super.key, this.initialTabIndex});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  late MapController _sharedMapController; // Add shared MapController
  bool _handledFocusArgs = false; // Ensure focus-by-args runs once
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Place> _searchResults = [];
  List<Place> _allPlaces = [];

  @override
  void initState() {
    super.initState();
    _sharedMapController = MapController();
    _selectedIndex = widget.initialTabIndex ?? 0;
    _loadPlaces();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      });
      return;
    }

    final lower = query.toLowerCase();
    final placesWithCoordinates = _allPlaces
        .where(
          (place) =>
              place.name.toLowerCase().contains(lower) ||
              place.description.toLowerCase().contains(lower),
        )
        .toList();

    setState(() {
      _searchResults = placesWithCoordinates;
    });

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
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(place.description),
                                const SizedBox(height: 4),
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: Colors.deepPurple,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Sumber: Groundcheck',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: const Icon(
                              Icons.map,
                              color: Colors.green,
                              size: 16,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _sharedMapController.move(place.position, 18.0);
                              if (_selectedIndex != 0) {
                                setState(() {
                                  _selectedIndex = 0;
                                });
                              }
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                              context.read<MapBloc>().add(PlaceSelected(place));
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

  void _focusGroundcheckLocation(GroundcheckRecord record) {
    final lat = double.tryParse(record.latitude);
    final lon = double.tryParse(record.longitude);

    if (lat == null || lon == null || lat == 0.0 || lon == 0.0) return;

    setState(() {
      _selectedIndex = 0;
    });

    try {
      // Use latlong2.LatLng via flutter_map export
      _sharedMapController.move(LatLng(lat, lon), 18.0);
    } catch (_) {}
  }

  Widget _buildOverlayContent() {
    switch (_selectedIndex) {
      case 0:
        return MapPage(mapController: _sharedMapController);
      case 1:
        return DashboardPage(mapController: _sharedMapController);
      case 2:
        return const ContributionPage();
      case 3:
        return GroundcheckPage(onGoToMap: _focusGroundcheckLocation);
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
          MapPage(mapController: _sharedMapController),
          // Overlay content: keep pages mounted to preserve state across tab changes
          Offstage(
            offstage: _selectedIndex == 0,
            child: IndexedStack(
              index: _selectedIndex == 0 ? 0 : _selectedIndex - 1,
              children: [
                DashboardPage(mapController: _sharedMapController),
                const GroundcheckHistoryPage(),
                GroundcheckPage(onGoToMap: _focusGroundcheckLocation),
              ],
            ),
          ),
          // Floating search bar with avatar (Google Maps style) - only on Jelajah tab
          if (_selectedIndex == 0)
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
                      color: Colors.black.withValues(alpha: 0.2),
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
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Kontribusi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Groundcheck',
          ),
        ],
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
