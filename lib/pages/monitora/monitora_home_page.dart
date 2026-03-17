import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../theme/app_theme.dart';

// Pages destino
import 'monitora_new_monitoring_page.dart';
import 'monitora_new_trap_monitoring_page.dart';
import 'monitora_agro_apply_page.dart';

class HomeMonitoraPage extends StatelessWidget {
  const HomeMonitoraPage({super.key});

  // ✅ MISMO FONDO LOCAL QUE ADMIN
  static const String _bgAsset = 'assets/images/fondos.png';
  static const String _logoSvg = 'assets/icons/logo.svg';

  static const Color _agroAccent = Color(0xFFF55000);

  Future<void> _logout(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'logout',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const _ConfirmLogoutDialog(),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
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
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }

  void _openProfile(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'profile',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _ProfileDialog(),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
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
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: SvgPicture.asset(
          _logoSvg,
          height: 46,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        actions: [
          IconButton(
            tooltip: 'Perfil',
            onPressed: () => _openProfile(context),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
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
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.72)),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final cols = w >= 1200
                      ? 3
                      : w >= 760
                      ? 2
                      : 1;

                  return GridView.count(
                    crossAxisCount: cols,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: cols == 1 ? 2.7 : 3.2,
                    children: [
                      _MonitoraCard(
                        accent: accent,
                        title: 'Monitoreo de plaga',
                        subtitle: 'Selecciona invernadero, capilla y línea',
                        icon: Icons.bug_report_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MonitoraNewMonitoringPage(),
                          ),
                        ),
                      ),
                      _MonitoraCard(
                        accent: accent,
                        title: 'Monitoreo de trampas',
                        subtitle: 'Selecciona invernadero y capilla',
                        icon: Icons.local_offer_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const MonitoraNewTrapMonitoringPage(),
                          ),
                        ),
                      ),
                      _MonitoraCard(
                        accent: _agroAccent,
                        title: 'Aplicar agroquímicos',
                        subtitle: 'Aplicación a FOCO o general',
                        icon: Icons.science_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MonitoraAgroApplyPage(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitoraCard extends StatefulWidget {
  final Color accent;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _MonitoraCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_MonitoraCard> createState() => _MonitoraCardState();
}

class _MonitoraCardState extends State<_MonitoraCard> {
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
          transform: Matrix4.translationValues(0.0, _hover ? -3.0 : 0.0, 0.0),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(widget.icon, color: widget.accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.70),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_rounded, color: accent, size: 62),
                    const SizedBox(height: 10),
                    const Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '¿Seguro que quieres salir?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.72),
                      ),
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
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
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

class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog();

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: uid == null
                    ? const Text('Sin sesión')
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('app_users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snap) {
                          final data = snap.data?.data();
                          final email = (data?['email'] ?? user?.email ?? '')
                              .toString();
                          final name = (data?['fullName'] ?? '').toString();

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.isEmpty ? 'Mi perfil' : name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(email),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
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
