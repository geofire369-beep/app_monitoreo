import 'package:flutter/material.dart';
import '../../routes/routes_names.dart';
import '../../widgets/loading_pepper_screen.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // ✅ Mostrar loading fijo ~7s (sin navegar "a otra" pantalla intermedia)
    await Future.delayed(const Duration(seconds: 10));

    if (!mounted) return;

    // ✅ Al terminar, mandas al login (reemplazo para que no regrese al loader)
    Navigator.of(context).pushReplacementNamed(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingPepperScreen(
      assetPath: 'assets/icons/pimiento.svg',
      size: 140, // si tu widget tiene "size"
    );
  }
}
