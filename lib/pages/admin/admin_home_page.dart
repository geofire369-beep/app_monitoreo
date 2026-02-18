import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../theme/app_theme.dart';
import '../../routes/routes_names.dart';
import 'admin_register_user_page.dart';
import 'admin_monitoreo_page.dart';

// Páginas nuevas (sin mapa)
import '../admin/agro/agro_applications_page.dart';
import '../admin/reports/reports_page.dart';

// ✅ NUEVO
import '../admin/catalogos/admin_catalogos_page.dart';

class HomeAdminPage extends StatelessWidget {
  const HomeAdminPage({super.key});

  static const String _bgAsset = 'assets/images/fondos.png';

  Future<void> _logout(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'logout',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const _ConfirmLogoutDialog(),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, RouteNames.login, (_) => false);
    }
  }

  void _showProfile(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'profile',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _ProfileDialog(),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1200 ? 3 : w >= 760 ? 2 : 1;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.pepperRed,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,

        // ✅ QUITA LA FLECHA
        automaticallyImplyLeading: false,

        title: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/logo.svg',
              height: 46,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 10),
          ],
        ),
        actions: [
          _ActionIcon(
            tooltip: 'Mi perfil',
            icon: Icons.account_circle_outlined,
            onTap: () => _showProfile(context),
          ),
          _ActionIcon(
            tooltip: 'Cerrar sesión',
            icon: Icons.logout_rounded,
            onTap: () => _logout(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Container(color: Colors.white),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.72)),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cols == 1 ? 2.7 : 3.2,
                children: [
                  _AdminCard(
                    title: 'Alta de usuarios',
                    subtitle: 'Registrar monitoras y administrativos',
                    icon: Icons.person_add_alt_1,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminRegisterUserPage()),
                      );
                    },
                  ),
                  _AdminCard(
                    title: 'Agroquímicos',
                    subtitle: 'Registro de aplicaciones',
                    icon: Icons.science_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AgroApplicationsPage()),
                      );
                    },
                  ),
                  _AdminCard(
                    title: 'Reportes',
                    subtitle: 'Tablas, incidencia y exportación',
                    icon: Icons.bar_chart_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportsPage()),
                      );
                    },
                  ),
                  _AdminCard(
                    title: 'Catálogos',
                    subtitle: 'Plagas, agroquímicos y ....',
                    icon: Icons.list_alt_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminCatalogosPage()),
                      );
                    },
                  ),
                  _AdminCard(
                    title: 'Monitoreo',
                    subtitle: 'Ver avance y plagas sobre el mapa',
                    icon: Icons.travel_explore_rounded,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminMonitoreoPage()),
                      );
                    },
                  ),
                  _AdminCard(
                    title: 'Mapa',
                    subtitle: 'Editor de mapas de invernadero',
                    icon: Icons.map_outlined,
                    onTap: () => Navigator.pushNamed(context, RouteNames.adminMapas),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ Botón del AppBar con “feedback” bonito
class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _AdminCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<_AdminCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.identity()..translate(0.0, _hover ? -3.0 : 0.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.16 : 0.10),
                blurRadius: _hover ? 20 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppTheme.pepperRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(widget.icon, color: AppTheme.pepperRed),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.black.withValues(alpha: 0.45)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmLogoutDialog extends StatelessWidget {
  const _ConfirmLogoutDialog();

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 14,
              shadowColor: Colors.black.withValues(alpha: 0.22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_rounded, color: accent, size: 62),
                    const SizedBox(height: 10),
                    const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(
                      '¿Seguro que quieres salir?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.72)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Salir'),
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
    );
  }
}

// ✅ PERFIL PRO: nombre, correo, rol (badge)
class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog();

  String _prettyRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return 'Administrativo';
    if (r == 'monitora') return 'Monitora';
    return 'Desconocido';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 14,
              shadowColor: Colors.black.withValues(alpha: 0.28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: uid == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: accent, size: 56),
                          const SizedBox(height: 10),
                          const Text('Sin sesión', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ),
                        ],
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('app_users').doc(uid).snapshots(),
                        builder: (context, snap) {
                          final data = snap.data?.data() ?? {};
                          final email = (data['email'] ?? user?.email ?? '').toString();
                          final name = (data['fullName'] ?? data['name'] ?? '').toString();
                          final roleRaw = (data['role'] ?? '').toString();
                          final role = _prettyRole(roleRaw);

                          final initials = (name.trim().isEmpty)
                              ? 'A'
                              : name.trim().split(RegExp(r'\s+')).take(2).map((x) => x[0]).join().toUpperCase();

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: accent.withValues(alpha: 0.14)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: accent.withValues(alpha: 0.20)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          initials,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name.trim().isEmpty ? 'Mi perfil' : name.trim(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.badge_outlined, size: 16, color: accent),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      role,
                                                      style: TextStyle(fontWeight: FontWeight.w900, color: accent),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cerrar',
                                      onPressed: () => Navigator.pop(context),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Datos
                              _ProfileRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Nombre',
                                value: name.trim().isEmpty ? '—' : name.trim(),
                                accent: accent,
                              ),
                              const SizedBox(height: 10),
                              _ProfileRow(
                                icon: Icons.email_outlined,
                                label: 'Correo',
                                value: email.trim().isEmpty ? '—' : email.trim(),
                                accent: accent,
                              ),
                              const SizedBox(height: 10),
                              _ProfileRow(
                                icon: Icons.security_outlined,
                                label: 'Rol',
                                value: role,
                                accent: accent,
                              ),

                              const SizedBox(height: 14),

                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.black.withValues(alpha: 0.60), fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
