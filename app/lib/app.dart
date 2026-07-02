import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class NexusApp extends ConsumerWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final dark = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Nexus AI',
      debugShowCheckedModeBanner: false,
      theme: NexusTheme.light(),
      darkTheme: NexusTheme.dark(),
      themeMode: switch (dark) {
        null => ThemeMode.system,
        true => ThemeMode.dark,
        false => ThemeMode.light,
      },
      routerConfig: router,
    );
  }
}
