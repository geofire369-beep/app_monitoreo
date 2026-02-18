import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../theme/app_theme.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const String _bgUrl =
      'https://res.cloudinary.com/compo-com/image/fetch/c_fill,g_xy_center,f_auto,w_708,h_531,x_iw_mul_50_div_100,y_ih_mul_50_div_100/https://www.compo.de/dam/jcr:bf57712a-913c-47a1-9361-22d234fab0de/bell-pepper_paprika-1.jpg';

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _toast(String message, {bool ok = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: ok
            ? AppTheme.pepperGreen.withValues(alpha: 0.95)
            : Colors.black.withValues(alpha: 0.88),
        content: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.info, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<bool> _emailExistsInDb(String email) async {
    // ✅ Revisa en Firestore si existe un usuario con ese email EN app_users
    final snap = await FirebaseFirestore.instance
        .collection('app_users') // ✅ CAMBIO AQUÍ
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  Future<void> _sendReset() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    setState(() => _loading = true);

    try {
      // 1) Validar en tu BD (Firestore)
      final exists = await _emailExistsInDb(email);

      if (!mounted) return;

      if (!exists) {
        _toast(
          'El correo asociado no existe en nuestros registros 🙂',
          ok: false,
        );
        return;
      }

      // 2) Si existe, mandar reset con Firebase Auth
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _toast('Listo ✅ Te enviamos un correo para restablecer tu contraseña.', ok: true);
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final msg = switch (e.code) {
        'invalid-email' => 'El correo no es válido.',
        _ => 'No se pudo enviar el correo. Intenta de nuevo.',
      };
      _toast(msg, ok: false);
    } catch (_) {
      if (!mounted) return;
      _toast('Ocurrió un error inesperado.', ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar contraseña'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              _bgUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Colors.white),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(color: Colors.white);
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const SizedBox(height: 52),
                      const _PepperSvgBadge(color: AppTheme.pepperYellow),
                      const SizedBox(height: 16),
                      Text(
                        '¿Olvidaste tu contraseña?',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Escribe tu correo y te enviaremos un enlace para restablecerla.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _sendReset(),
                                  decoration:
                                      const InputDecoration(labelText: 'Correo'),
                                  validator: (v) {
                                    final s = (v ?? '').trim();
                                    if (s.isEmpty) return 'Ingresa tu correo';
                                    if (!s.contains('@')) return 'Correo inválido';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _sendReset,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.pepperYellow,
                                      foregroundColor: Colors.white,
                                      shadowColor: AppTheme.pepperYellow
                                          .withValues(alpha: 0.35),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Enviar enlace'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: Text(
                                    'Volver al login',
                                    style: TextStyle(color: cs.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '© 2026 Geopónica. Todos los derechos reservados.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PepperSvgBadge extends StatelessWidget {
  final Color color;
  const _PepperSvgBadge({required this.color});

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/pimiento.svg',
          width: _size * 0.62,
          height: _size * 0.62,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}
