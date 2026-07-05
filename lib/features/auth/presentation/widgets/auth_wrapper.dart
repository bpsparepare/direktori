import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import '../bloc/auth_bloc.dart';
import '../pages/login_page.dart';
import '../../../map/data/repositories/map_repository_impl.dart';
import '../../../map/domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../../../map/domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../../map/domain/usecases/get_initial_map_config.dart';
import '../../../map/domain/usecases/get_places.dart';
import '../../../map/domain/usecases/get_places_by_sls.dart';
import '../../../map/domain/usecases/get_places_in_bounds.dart';
import '../../../map/domain/usecases/get_polygon_points.dart';
import '../../../map/domain/usecases/refresh_places.dart';
import '../../../map/presentation/bloc/map_bloc.dart';
import '../../../map/presentation/bloc/map_event.dart';
import '../../../map/presentation/pages/main_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) {
        final previousUserId = previous is AuthAuthenticated
            ? previous.user.id
            : null;
        final currentUserId = current is AuthAuthenticated ? current.user.id : null;
        return previousUserId != currentUserId;
      },
      listener: (context, state) {
        context.read<MapRepositoryImpl>().clearSessionCaches();
      },
      builder: (context, state) {
        developer.log(
          '🔄 AuthWrapper: Current state: ${state.runtimeType}',
          name: 'AuthWrapper',
        );

        if (state is AuthLoading || state is AuthInitial) {
          developer.log(
            '⏳ AuthWrapper: Showing loading screen',
            name: 'AuthWrapper',
          );
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is AuthAuthenticated) {
          developer.log(
            '✅ AuthWrapper: User authenticated, navigating to MainPage',
            name: 'AuthWrapper',
          );
          developer.log(
            '✅ AuthWrapper: User email: ${state.user.email}',
            name: 'AuthWrapper',
          );
          final mapRepository = context.read<MapRepositoryImpl>();
          return BlocProvider<MapBloc>(
            key: ValueKey('map-bloc-${state.user.id}'),
            create: (_) =>
                MapBloc(
                    getInitialMapConfig: GetInitialMapConfig(mapRepository),
                    getPlaces: GetPlaces(mapRepository),
                    getPlacesBySls: GetPlacesBySls(mapRepository),
                    refreshPlaces: RefreshPlaces(mapRepository),
                    getPlacesInBounds: GetPlacesInBounds(mapRepository),
                    getFirstPolygonMeta: GetFirstPolygonMetaFromGeoJson(
                      mapRepository,
                    ),
                    getAllPolygonsMeta: GetAllPolygonsMetaFromGeoJson(
                      mapRepository,
                    ),
                    getPolygonPoints: GetPolygonPoints(mapRepository),
                  )
                  ..add(const MapInitRequested())
                  ..add(const PlacesRequested())
                  ..add(const PolygonsListRequested()),
            child: MainPage(key: ValueKey('main-page-${state.user.id}')),
          );
        }

        if (state is AuthError) {
          developer.log(
            '❌ AuthWrapper: Auth error: ${state.message}',
            name: 'AuthWrapper',
          );
        }

        developer.log('🔄 AuthWrapper: Showing LoginPage', name: 'AuthWrapper');
        return const LoginPage();
      },
    );
  }
}
