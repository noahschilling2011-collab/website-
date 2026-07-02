import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_ai/core/theme/app_theme.dart';

void main() {
  group('NexusTheme', () {
    test('light and dark themes use Material 3', () {
      expect(NexusTheme.light().useMaterial3, isTrue);
      expect(NexusTheme.dark().useMaterial3, isTrue);
    });

    test('brightness matches the variant', () {
      expect(NexusTheme.light().colorScheme.brightness, Brightness.light);
      expect(NexusTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('iOS uses Cupertino page transitions', () {
      final builders = NexusTheme.light().pageTransitionsTheme.builders;
      expect(builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    });
  });
}
