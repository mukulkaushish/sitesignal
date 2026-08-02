import 'package:flutter/animation.dart';

/// Shared visual tokens adapted from the digii-mobile design system.
abstract final class AppDimensions {
  static const double breakpointSidebar = 960;
  static const double contentMaxWidth = 1180;
  static const double settingsMaxWidth = 820;

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  static const double r4 = 4;
  static const double r6 = 6;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;

  static const double borderThin = 1;
  static const double buttonHeight = 44;
  static const double iconXs = 14;
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 48;

  static const double pagePadding = 24;

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 350);
  static const Curve easeStandard = Curves.easeOutCubic;

  static const double accentFillHero = 0.08;
  static const double accentFillChip = 0.10;
  static const double accentBorderSubtle = 0.25;

  /// Horizontal padding that keeps a page's content centered under
  /// [contentWidth] once the viewport grows wider than it, and falls back to
  /// [pagePadding] on narrower/compact layouts.
  static double centeredHorizontalPadding(
    double maxWidth,
    double contentWidth,
  ) {
    return maxWidth > contentWidth + (pagePadding * 2)
        ? (maxWidth - contentWidth) / 2
        : pagePadding;
  }
}
