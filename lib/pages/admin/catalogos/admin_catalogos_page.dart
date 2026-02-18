import 'package:flutter/material.dart';
import 'package:sdp/pages/admin/catalogos/agro_productos_page.dart';

import '../../../theme/app_theme.dart';
import 'admin_plagas_page.dart';

class AdminCatalogosPage extends StatelessWidget {
  const AdminCatalogosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Catálogos'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _CatalogTile(
              icon: Icons.bug_report_outlined,
              title: 'Plagas',
              subtitle: 'Registrar / editar / eliminar plagas y enfermedades',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPlagasPage()),
                );
              },
            ),

            // Dejas los placeholders para después si quieres:
            const SizedBox(height: 10),
            _CatalogTile(
              icon: Icons.medication,
              title: 'Productos Agroquímicos',
              subtitle: 'Próximamente ',
              onTap: () {
                navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AgroProductosPage()),
                );
              },
            ),
            const SizedBox(height: 10),
            
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _CatalogTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.black.withValues(alpha: 0.70))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.black.withValues(alpha: 0.45)),
           