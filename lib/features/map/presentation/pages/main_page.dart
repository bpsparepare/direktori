import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'map_page.dart';
import 'saved_page.dart';
import 'contribution_page.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  late MapController _sharedMapController; // Add shared MapController

  @override
  void initState() {
    super.initState();
    _sharedMapController = MapController(); // Initialize shared MapController
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
}
