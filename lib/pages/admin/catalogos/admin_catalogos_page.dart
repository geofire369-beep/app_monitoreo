import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../theme/app_theme.dart';
import 'admin_plagas_page.dart';
import 'agro_productos_page.dart';

class AdminCatalogosPage extends StatelessWidget {
  const AdminCatalogosPage({super.key});

  static const String _bgAsset = 'assets/images/fondos.png';

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text(
          'Catálogos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withValues(alpha: 0.14),
                      const Color(0xFFF7F7F7),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.86),
                    Colors.white.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;

                final cols = w >= 1100
                    ? 2
                    : w >= 700
                    ? 2
                    : 1;

                final aspect = w >= 1100
                    ? 1.95
                    : w >= 700
                    ? 1.35
                    : 1.18;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                  children: [
                    _DashboardHero(accent: accent),
                    const SizedBox(height: 14),
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: aspect,
                      ),
                      children: [
                        _CatalogModuleCard(
                          accent: accent,
                          tone: const Color(0xFFCB5A1A),
                          icon: Icons.bug_report_outlined,
                          title: 'Plagas',
                          subtitle:
                              'Registrar, editar y organizar plagas y enfermedades del sistema.',
                          bullets: const [
                            'Altas y edición rápida',
                            'Niveles y clasificación',
                            'Favoritos para monitoreo',
                          ],
                          tag: 'Gestión biológica',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminPlagasPage(),
                            ),
                          ),
                        ),
                        _CatalogModuleCard(
                          accent: accent,
                          tone: const Color(0xFF2E7D6B),
                          icon: Icons.medication_outlined,
                          title: 'Productos agroquímicos',
                          subtitle:
                              'Administrar productos, fabricantes y datos del catálogo operativo.',
                          bullets: const [
                            'Catálogo de productos',
                            'Fabricantes y datos',
                            'Control administrativo',
                          ],
                          tag: 'Inventario técnico',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AgroProductosPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  final Color accent;

  const _DashboardHero({required this.accent});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 24,
      glowColor: accent.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            _HeroIcon(accent: accent, icon: Icons.dashboard_customize_rounded),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centro de catálogos',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Accede a los módulos administrativos del sistema.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.3,
                      height: 1.22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogModuleCard extends StatefulWidget {
  final Color accent;
  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final String tag;
  final VoidCallback onTap;
  final bool enabled;

  const _CatalogModuleCard({
    required this.accent,
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.tag,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_CatalogModuleCard> createState() => _CatalogModuleCardState();
}

class _CatalogModuleCardState extends State<_CatalogModuleCard> {
  bool _hover = false;
  bool _down = false;

  bool get _canHover => kIsWeb;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final scale = !enabled ? 1.0 : (_down ? 0.988 : (_hover ? 1.008 : 1.0));

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: MouseRegion(
        onEnter: (_) =>
            _canHover && enabled ? setState(() => _hover = true) : null,
        onExit: (_) =>
            _canHover && enabled ? setState(() => _hover = false) : null,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: _GlassPanel(
              radius: 24,
              borderColor: _hover && enabled
                  ? widget.tone.withValues(alpha: 0.26)
                  : Colors.black.withValues(alpha: 0.07),
              glowColor: widget.tone.withValues(
                alpha: _hover && enabled ? 0.15 : 0.08,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: enabled ? widget.onTap : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.tone.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: -14,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.accent.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ModuleIcon(
                                accent: widget.tone,
                                icon: widget.icon,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: _TagBadge(
                                      color: widget.tone,
                                      text: widget.tag,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.68),
                              fontWeight: FontWeight.w600,
                              height: 1.18,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: widget.bullets
                                  .take(3)
                                  .map(
                                    (b) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: widget.tone,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              b,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.black.withValues(
                                                  alpha: 0.72,
                                                ),
                                                fontWeight: FontWeight.w700,
                                                height: 1.1,
                                                fontSize: 12.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  widget.tone.withValues(alpha: 0.12),
                                  widget.tone.withValues(alpha: 0.04),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: widget.tone.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    enabled ? 'Abrir módulo' : 'Deshabilitado',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: widget.tone,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: widget.tone,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _HeroIcon({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }
}

class _ModuleIcon extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _ModuleIcon({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, color: accent, size: 22),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final Color color;
  final String text;

  const _TagBadge({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10.8,
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color? borderColor;
  final Color? glowColor;

  const _GlassPanel({
    required this.child,
    this.radius = 22,
    this.borderColor,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? Colors.black.withValues(alpha: 0.07);
    final glow = glowColor ?? Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: glow, blurRadius: 24, offset: const Offset(0, 12)),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
