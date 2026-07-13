import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/code/code_editor_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/tasks/tasks_screen.dart';
import '../../features/tools/tools_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the auth state changes.
  final refreshNotifier = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, __) => refreshNotifier.value++);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/chat',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final signedIn = ref.read(authControllerProvider) is SignedIn;
      final onLogin = state.matchedLocation == '/login';
      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/chat';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, __) => const ChatScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/tools',
              builder: (_, __) => const ToolsScreen(),
              routes: [GoRoute(path: 'code', builder: (_, __) => const CodeEditorScreen())],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/notes', builder: (_, __) => const NotesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen())]),
        ],
      ),
    ],
  );
});
