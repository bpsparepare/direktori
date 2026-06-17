import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config/supabase_config.dart';
import 'core/services/image_service_locator.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/usecases/get_current_user_usecase.dart';
import 'features/auth/domain/usecases/sign_in_with_email_usecase.dart';
import 'features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'features/auth/domain/usecases/sign_out_usecase.dart';
import 'features/auth/presentation/widgets/auth_wrapper.dart';
import 'core/widgets/version_check_wrapper.dart';
import 'features/map/data/repositories/map_repository_impl.dart';
// import 'core/widgets/debug_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final webViewDataDir = Directory('${supportDir.path}\\webview_data');
      if (!await webViewDataDir.exists()) {
        await webViewDataDir.create(recursive: true);
      }

      await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: webViewDataDir.path,
        ),
      );
    } catch (e) {
      debugPrint("Failed to initialize WebViewEnvironment: $e");
    }
  }

  try {
    await dotenv.load(fileName: 'assets/env');
  } catch (_) {}

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

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepositoryImpl>.value(value: authRepository),
        RepositoryProvider<MapRepositoryImpl>.value(value: mapRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              getCurrentUserUseCase: GetCurrentUserUseCase(authRepository),
              signInWithEmailUseCase: SignInWithEmailUseCase(authRepository),
              signInWithGoogleUseCase: SignInWithGoogleUseCase(authRepository),
              signOutUseCase: SignOutUseCase(authRepository),
            )..add(AuthCheckRequested()),
          ),
        ],
        child: MaterialApp(
          title: 'Direktori',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: const VersionCheckWrapper(child: AuthWrapper()),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
