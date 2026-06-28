import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_currency_app/main.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  setUpAll(() async {
    await Hive.initFlutter();
    await Hive.openBox('settings');
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartCurrencyApp()));
    
    // We expect the GoRouter to navigate to the CameraScreen
    await tester.pumpAndSettle();
    
    expect(find.text('Ready to scan'), findsOneWidget);
  });
}
