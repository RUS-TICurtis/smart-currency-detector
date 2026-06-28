import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_theme.dart';
import 'routes/app_router.dart';

void main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage
  await Hive.initFlutter();
  await Hive.openBox('settings');

  runApp(
    // ProviderScope stores the state of all the providers we create
    const ProviderScope(
      child: SmartCurrencyApp(),
    ),
  );
}

class SmartCurrencyApp extends ConsumerWidget {
  const SmartCurrencyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the router provider
    final goRouter = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Smart Currency Detector',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Automatically switch between light and dark
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
