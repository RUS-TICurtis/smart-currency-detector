import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_theme.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX (L-09): Global Flutter error handler.
  // In release mode this prevents the red-screen-of-death and logs silently.
  // In debug mode the default error presenter is retained for development.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      // Log to your crash reporting service here (e.g. Firebase Crashlytics).
      debugPrint('Uncaught Flutter error: ${details.exceptionAsString()}');
    } else {
      FlutterError.presentError(details);
    }
  };

  // Initialise local storage before launching the app.
  await Hive.initFlutter();
  await Hive.openBox('settings');

  runApp(
    // ProviderScope holds the state of all Riverpod providers.
    const ProviderScope(
      child: SmartCurrencyApp(),
    ),
  );
}

class SmartCurrencyApp extends ConsumerWidget {
  const SmartCurrencyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Smart Currency Detector',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
