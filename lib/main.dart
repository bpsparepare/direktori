import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as dotenv;

import 'core/config/supabase_config.dart';
import 'core/services/image_service_locator.dart';
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
import 'features/contribution/presentation/bloc/contribution_bloc.dart';
import 'features/contribution/data/repositories/contribution_repository_impl.dart';
import 'features/contribution/data/datasources/contribution_remote_datasource.dart';
import 'features/contribution/domain/usecases/create_contribution_usecase.dart';
import 'features/contribution/domain/usecases/get_user_stats_usecase.dart';
import 'features/contribution/domain/usecases/get_user_contributions_usecase.dart';
import 'features/contribution/domain/usecases/get_leaderboard_usecase.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // For Windows builds with dart-define-from-file, environment variables
  // are injected at build time, so we use dart-define values directly
  print('✅ Using dart-define environment variables for Windows build');

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize Image Service with Upload API on shared hosting
  print('🔄 Initializing Upload API service...');
  await ImageServiceLocator.initializeWithUploadApi();
  print(
    '✅ Upload API service initialized: ${ImageServiceLocator.currentServiceName}',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize repositories
    final authRepository = AuthRepositoryImpl();
    final mapRepository = MapRepositoryImpl();
    final contributionRepository = ContributionRepositoryImpl(
      remoteDataSource: ContributionRemoteDataSourceImpl(
        supabaseClient: SupabaseConfig.client,
      ),
    );

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
                ..add(const PolygonsListRequested()),
        ),
        BlocProvider<ContributionBloc>(
          create: (context) => ContributionBloc(
            repository: contributionRepository,
            createContributionUseCase: CreateContributionUseCase(
              contributionRepository,
            ),
            getUserStatsUseCase: GetUserStatsUseCase(contributionRepository),
            getUserContributionsUseCase: GetUserContributionsUseCase(
              contributionRepository,
            ),
            getLeaderboardUseCase: GetLeaderboardUseCase(
              contributionRepository,
            ),
          ),
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
