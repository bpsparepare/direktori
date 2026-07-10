import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'map_page.dart';
import 'kbli_page.dart';
import 'dokumentasi_page.dart';
import 'fasih_dashboard_page.dart';
import 'usaha_organik_page.dart';
import 'nik_tidak_valid_page.dart';
import 'anomali_page.dart';
import 'analisis_page.dart';
import 'import_anomali_pusat_page.dart';
import 'responden_sulit_page.dart';
import 'lembar_kerja_page.dart';
import '../widgets/documentation_upload_dialog.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../domain/entities/place.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class MainPage extends StatefulWidget {
  final int? initialTabIndex;
  const MainPage({super.key, this.initialTabIndex});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  int _bottomNavIndex = 0;
  late MapController _sharedMapController; // Add shared MapController
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<int> _documentationRefreshSignal = ValueNotifier<int>(0);
  List<Place> _searchResults = [];
  List<Place> _allPlaces = [];
  String? _se2026Role;

  @override
  void initState() {
    super.initState();
    _sharedMapController = MapController();
    _selectedIndex = widget.initialTabIndex ?? 0;
    _bottomNavIndex = _selectedIndex <= 2 ? _selectedIndex : 0;
    _loadPlaces();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    final service = GroundcheckSupabaseService();
    final role = await service.fetchCurrentSe2026Role();
    if (mounted) {
      setState(() {
        _se2026Role = role;
      });
    }
  }

  void _loadPlaces() async {
    // Load dummy places from repository
    final repository = MapRepositoryImpl();
    _allPlaces = await repository.getPlaces();
  }

  @override
  void dispose() {
    _documentationRefreshSignal.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  /// Buka SLS tertentu di peta (tab Jelajah) beserta progresnya. Dipanggil dari
  /// FasihDashboardPage saat baris SLS ditekan. [slsUnitId] = kode wilayah 16
  /// digit yang dicocokkan ke `idsubsls` polygon (fallback `idsls`).
  void _openSlsOnMap(String slsUnitId, String slsLabel) {
    final mapBloc = context.read<MapBloc>();
    final metas = mapBloc.state.polygonsMeta;
    final target = slsUnitId.trim();

    int idx = metas.indexWhere((p) => (p.idsubsls ?? '').trim() == target);
    if (idx < 0) {
      idx = metas.indexWhere((p) => (p.idsls ?? '').trim() == target);
    }

    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SLS "$slsLabel" belum tersedia di peta'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    mapBloc.add(PolygonSelectedByIndex(idx));
    setState(() {
      _selectedIndex = 0;
      _bottomNavIndex = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Menampilkan SLS $slsLabel di peta'),
        backgroundColor: const Color(0xFF1D8F5A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _navigateToIndex(int index, {bool closeDrawer = false}) {
    if (closeDrawer) {
      Navigator.of(context).pop();
    }

    context.read<MapBloc>().add(const PlaceCleared());
    setState(() {
      _selectedIndex = index;
      if (index <= 2) {
        _bottomNavIndex = index;
      }
    });
  }

  Future<void> _openDocumentationUploadFromExplore() async {
    final entry = await showDocumentationUploadDialog(context);
    if (!mounted || entry == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Upload dokumentasi berhasil'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    _documentationRefreshSignal.value++;
    _navigateToIndex(3);
  }

  Widget _buildDrawerButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required IconData icon,
    required String title,
    required int index,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: _selectedIndex == index,
      onTap: () => _navigateToIndex(index, closeDrawer: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) => previous.places != current.places,
      listener: (context, state) {
        if (state.status == MapStatus.success) {
          setState(() {
            _allPlaces = state.places;
          });
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Menu Lainnya',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                _buildDrawerMenuItem(
                  icon: Icons.photo_camera_back_outlined,
                  title: 'Dokumentasi',
                  index: 3,
                ),
                _buildDrawerMenuItem(
                  icon: Icons.apartment_rounded,
                  title: 'KBLI',
                  index: 4,
                ),
                _buildDrawerMenuItem(
                  icon: Icons.eco_rounded,
                  title: 'Usaha Organik',
                  index: 5,
                ),
                _buildDrawerMenuItem(
                  icon: Icons.fingerprint,
                  title: 'NIK Tidak Valid',
                  index: 6,
                ),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Lembar Kerja'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LembarKerjaPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_search_rounded),
                  title: const Text('Responden Sulit'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RespondenSulitPage(),
                      ),
                    );
                  },
                ),
                if (_se2026Role == 'admin')
                  _buildDrawerMenuItem(
                    icon: Icons.query_stats_rounded,
                    title: 'Analisis',
                    index: 7,
                  ),
                if (_se2026Role == 'admin')
                  ListTile(
                    leading: const Icon(Icons.upload_file_rounded),
                    title: const Text('Impor Anomali Pusat'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ImportAnomaliPusatPage(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
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
                  FasihDashboardPage(onOpenSlsOnMap: _openSlsOnMap),
                  const AnomaliPage(),
                  DokumentasiPage(
                    refreshListenable: _documentationRefreshSignal,
                  ),
                  const KbliPage(),
                  const UsahaOrganikPage(),
                  const NikTidakValidPage(),
                  const AnalisisPage(),
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
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildDrawerButton(),
                      ),
                      // Search TextField
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: false,
                            onTapOutside: (event) {
                              _searchFocusNode.unfocus();
                            },
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
                              color: _avatarColor,
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
            if (_selectedIndex != 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: _buildDrawerButton(),
              ),
          ],
        ),
        floatingActionButton: _selectedIndex == 0
            ? BlocSelector<MapBloc, MapState, bool>(
                selector: (state) => state.markerEditMode,
                builder: (context, markerEditMode) {
                  // Sembunyikan FAB Dokumentasi saat mode edit posisi marker
                  // agar tidak menutupi bar Simpan/Batal.
                  if (markerEditMode) return const SizedBox.shrink();
                  return FloatingActionButton.extended(
                    heroTag: 'main_page_explore_fab',
                    onPressed: _openDocumentationUploadFromExplore,
                    backgroundColor: const Color(0xFF1D8F5A),
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Dokumentasi'),
                  );
                },
              )
            : null,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _bottomNavIndex,
          onTap: _navigateToIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: 'Jelajah',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.report_problem_outlined),
              label: 'Anomali',
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

  Color get _avatarColor {
    switch (_se2026Role) {
      case 'admin':
        return Colors.deepPurple;
      case 'pengawas':
        return Colors.orange;
      case 'pendata':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }
}
