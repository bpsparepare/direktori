import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/config/supabase_config.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/usecases/get_current_user_usecase.dart';
import 'features/auth/domain/usecases/sign_in_with_email_usecase.dart';
import 'features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'features/auth/domain/usecases/sign_out_usecase.dart';
import 'features/auth/presentation/widgets/auth_wrapper.dart';
import 'features/map/presentation/bloc/map_bloc.dart';
import 'features/map/presentation/bloc/map_event.dart';
import 'features/map/data/repositories/map_repository_impl.dart';
import 'features/map/domain/usecases/get_initial_map_config.dart';
import 'features/map/domain/usecases/get_places.dart';
import 'features/map/domain/usecases/get_first_polygon_meta_from_geojson.dart';
import 'features/map/domain/usecases/get_all_polygons_meta_from_geojson.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize repositories
    final authRepository = AuthRepositoryImpl();
    final mapRepository = MapRepositoryImpl();

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            getCurrentUserUseCase: GetCurrentUserUseCase(authRepository),
            signInWithEmailUseCase: SignInWithEmailUseCase(authRepository),
            signInWithGoogleUseCase: SignInWithGoogleUseCase(authRepository),
            signOutUseCase: SignOutUseCase(authRepository),
          )..add(AuthCheckRequested()),
        ),
        BlocProvider<MapBloc>(
          create: (context) =>
              MapBloc(
                  getInitialMapConfig: GetInitialMapConfig(mapRepository),
                  getPlaces: GetPlaces(mapRepository),
                  getFirstPolygonMeta: GetFirstPolygonMetaFromGeoJson(
                    mapRepository,
                  ),
                  getAllPolygonsMeta: GetAllPolygonsMetaFromGeoJson(
                    mapRepository,
                  ),
                )
                ..add(const MapInitRequested())
                ..add(const PlacesRequested())
                ..add(const PolygonRequested())
                ..add(const PolygonsListRequested()),
        ),
      ],
      child: MaterialApp(
        title: 'Direktori',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
