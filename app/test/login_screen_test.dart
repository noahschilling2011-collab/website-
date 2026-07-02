import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_ai/core/providers.dart';
import 'package:nexus_ai/core/storage/local_store.dart';
import 'package:nexus_ai/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('login screen shows email/password and switches to register mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nexus AI'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'E-Mail'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Passwort'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsNothing);

    await tester.tap(find.text('Neues Konto erstellen'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.text('Konto erstellen'), findsOneWidget);
  });
}
