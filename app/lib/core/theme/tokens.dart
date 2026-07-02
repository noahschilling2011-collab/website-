import 'package:flutter/material.dart';

/// Design tokens — the single source of truth of the Nexus design system.
/// Documented in docs/DESIGN_SYSTEM.md.
abstract final class NexusTokens {
  // Brand palette
  static const Color primary = Color(0xFF5B5FEF);
  static const Color primaryDark = Color(0xFF8B8DF5);
  static const Color accent = Color(0xFF00C2A8);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFF5A623);

  // Surfaces (light / dark)
  static const Color surfaceLight = Color(0xFFF7F7FA);
  static const Color surfaceDark = Color(0xFF101014);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF1A1A21);

  // Spacing scale (4pt grid)
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;

  // Radii
  static const double radiusS = 8;
  static const double radiusM = 14;
  static const double radiusL = 22;

  // Motion — Apple-like spring-ish curves and durations
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Curve easeOutExpo = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeSpring = Cubic(0.34, 1.56, 0.64, 1);
}
