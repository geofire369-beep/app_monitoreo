import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class MonitoraHistoryPage extends StatelessWidget {
  const MonitoraHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: AppTheme.pepperGreen,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Historial de monitoreos (pendiente).'),
      ),
    );
  }
}
