import 'package:flutter/material.dart';

class SiteSignalLogo extends StatelessWidget {
  const SiteSignalLogo({required this.size, super.key});

  static const assetPath = 'assets/app_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'SiteSignal',
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
