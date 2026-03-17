import 'package:flutter/material.dart';
import 'monitora_agro_apply_foco_new_page.dart';

class MonitoraAgroApplyPage extends StatelessWidget {
  const MonitoraAgroApplyPage({super.key});

  static const Color _agroAccent = Color(0xFFF55000);
  static const String _bgAsset = 'assets/images/fondos.png';

  @override
  Widget build(BuildContext context) {
    const accent = _agroAccent;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4EE),
      appBar: AppBar(
        title: const Text('Aplicar agroquímicos'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.78)),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.14),
                    const Color(0xFFFFF4EE).withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0.20),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _OptionCard(
                    accent: accent,
                    title: 'Aplicación a FOCO',
                    subtitle: 'Solo puntos con FOCO marcado',
                    icon: Icons.flash_on_rounded,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MonitoraAgroApplyFocoNewPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                 
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final Color accent;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _OptionCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = accent.withValues(alpha: 0.24);
    final glow = accent.withValues(alpha: 0.16);
    final radius = BorderRadius.circular(20);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCFA).withValues(alpha: 0.96),
            borderRadius: radius,
            border: Border.all(color: border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: glow,
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.28),
                      accent.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.26),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.black.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.64),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: accent.withValues(alpha: 0.78),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
