// lib/pages/login_page.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../routes/routes_names.dart';

enum UserRole { monitora, admin }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const String _prefsRememberKey = 'remember_me';

  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;
  bool _rememberMe = true;
  UserRole _role = UserRole.monitora;

  // Assets
  static const String _bgAsset = 'assets/images/login_bg.png';
  static const String _logoAsset = 'assets/icons/pimiento.svg';

  bool _keyboardOpen = false;
  bool _booted = false;

  // Animaciones de entrada
  late final AnimationController _introC;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  Color get _accent =>
      _role == UserRole.monitora ? AppTheme.pepperGreen : AppTheme.pepperRed;

  String get _roleLabel =>
      _role == UserRole.monitora ? 'Monitora' : 'Administrativo';

  // Naranja SOLO para la parte de recuperación/popup
  Color get _orange => const Color(0xFFFF7A00);
  Color get _orange2 => const Color(0xFFFF3D00);

  void _log(String msg) {
    if (kDebugMode) debugPrint('[LOGIN] $msg');
  }

  void _logError(Object e, [StackTrace? st]) {
    if (kDebugMode) {
      debugPrint('[LOGIN][ERROR] $e');
      if (st != null) debugPrint(st.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _introC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _introC, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _introC, curve: Curves.easeOutCubic));

    _emailFocus.addListener(() => mounted ? setState(() {}) : null);
    _passFocus.addListener(() => mounted ? setState(() {}) : null);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _introC.forward();
      await _boot();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _introC.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateKeyboardOpen();
  }

  void _updateKeyboardOpen() {
    final view = WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
        ? WidgetsBinding.instance.platformDispatcher.views.first
        : null;
    if (view == null) return;

    final bottomInsetLogical = view.viewInsets.bottom / view.devicePixelRatio;
    final isOpen = bottomInsetLogical > 0;

    if (isOpen != _keyboardOpen && mounted) {
      setState(() => _keyboardOpen = isOpen);
    }
  }

  // BOOT: solo remember + signOut si remember=false
  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;

    try {
      try {
        await precacheImage(const AssetImage(_bgAsset), context);
      } catch (e, st) {
        _logError(e, st);
      }

      _updateKeyboardOpen();

      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_prefsRememberKey) ?? true;

      if (!mounted) return;
      setState(() => _rememberMe = remember);

      final current = FirebaseAuth.instance.currentUser;

      if (current != null && !remember) {
        _log('CurrentUser exists but remember=false -> signOut');
        await FirebaseAuth.instance.signOut();
      }
    } catch (e, st) {
      _logError(e, st);
    }
  }

  Future<void> _saveRememberPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsRememberKey, _rememberMe);
    } catch (e, st) {
      _logError(e, st);
    }
  }

  Future<void> _applyAuthPersistence() async {
    if (!kIsWeb) return;
    try {
      await FirebaseAuth.instance.setPersistence(
        _rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
      _log('Web persistence set to ${_rememberMe ? "LOCAL" : "SESSION"}');
    } catch (e, st) {
      _logError(e, st);
    }
  }

  Future<Map<String, dynamic>?> _loadUserProfile(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('app_users')
        .doc(user.uid)
        .get();
    if (!doc.exists) return null;
    return doc.data();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    final email = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    try {
      await _applyAuthPersistence();
      await _saveRememberPreference();

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final user = cred.user;
      if (user == null) {
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Error',
            message: 'No se pudo iniciar sesión.',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      final data = await _loadUserProfile(user);
      if (data == null) {
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Acceso denegado',
            message:
                'Tu cuenta no está autorizada.\n\nContacta al administrador.',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      final role = (data['role'] ?? '').toString().toLowerCase();
      final active = (data['active'] ?? false) == true;

      if (!active) {
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Cuenta desactivada',
            message: 'Tu usuario está desactivado.\nContacta al administrador.',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      if (role != 'admin' && role != 'monitora') {
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Rol inválido',
            message: 'Rol inválido en BD.',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      final selected = _role == UserRole.admin ? 'admin' : 'monitora';
      if (selected != role) {
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Rol incorrecto',
            message:
                'Estás intentando entrar como "$selected", pero tu rol es "$role".',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      if (role == 'admin' && !user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (_) {}
        await FirebaseAuth.instance.signOut();
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showStatusPopup(
            ok: false,
            title: 'Verifica tu correo',
            message:
                'Tu correo no está verificado.\nRevisa tu bandeja (y SPAM) e intenta de nuevo.',
            accent: _orange,
            gradient: true,
          );
        }
        return;
      }

      HapticFeedback.lightImpact();
      if (!mounted) return;

      final nextRoute = (role == 'admin')
          ? RouteNames.homeAdmin
          : RouteNames.homeMonitora;
      Navigator.of(context).pushReplacementNamed(nextRoute);
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'Correo inválido.',
        'user-disabled' => 'Usuario deshabilitado.',
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'wrong-password' => 'Contraseña incorrecta.',
        'invalid-credential' => 'Correo o contraseña incorrectos.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        _ => e.message ?? 'Error: ${e.code}',
      };

      HapticFeedback.heavyImpact();
      if (mounted) {
        await _showStatusPopup(
          ok: false,
          title: 'No se pudo entrar',
          message: msg,
          accent: _orange,
          gradient: true,
        );
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        await _showStatusPopup(
          ok: false,
          title: 'Error',
          message: '$e',
          accent: _orange,
          gradient: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _userCtrl.text.trim());
    final emailFocus = FocusNode();
    bool submitting = false;

    final orange = _orange;
    final orange2 = _orange2;

    Future<void> sendReset(StateSetter setLocal) async {
      final email = emailCtrl.text.trim().toLowerCase();
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        HapticFeedback.heavyImpact();
        await _showStatusPopup(
          ok: false,
          title: 'Correo inválido',
          message: 'Escribe un correo válido.',
          accent: orange,
          gradient: true,
        );
        return;
      }

      setLocal(() => submitting = true);
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        HapticFeedback.mediumImpact();

        if (!mounted) return;
        Navigator.pop(context);

        await _showStatusPopup(
          ok: true,
          title: 'Correo enviado',
          message:
              'Se envió el enlace para restablecer tu contraseña.\n\nRevisa tu bandeja de entrada y también SPAM / No deseado.\n\nCorreo:\n$email',
          accent: orange,
          gradient: true,
        );
      } on FirebaseAuthException catch (e) {
        HapticFeedback.heavyImpact();
        await _showStatusPopup(
          ok: false,
          title: 'No se pudo enviar',
          message: e.message ?? e.code,
          accent: orange,
          gradient: true,
        );
      } catch (e) {
        HapticFeedback.heavyImpact();
        await _showStatusPopup(
          ok: false,
          title: 'Error',
          message: '$e',
          accent: orange,
          gradient: true,
        );
      } finally {
        if (mounted) setLocal(() => submitting = false);
      }
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'forgot_password',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext context, Animation<double> _, Animation<double> __) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final focused = emailFocus.hasFocus;

            return Material(
              type: MaterialType.transparency,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      elevation: 16,
                      shadowColor: Colors.black.withValues(alpha: 0.28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        orange.withValues(alpha: 0.22),
                                        orange2.withValues(alpha: 0.22),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: orange.withValues(alpha: 0.30),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.lock_reset_rounded,
                                    color: orange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Recuperar contraseña',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
                                  onPressed: submitting
                                      ? null
                                      : () => Navigator.pop(ctx),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Te enviaremos un enlace para cambiar tu contraseña.',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: focused
                                      ? orange.withValues(alpha: 0.55)
                                      : Colors.black.withValues(alpha: 0.10),
                                  width: focused ? 1.4 : 1.0,
                                ),
                              ),
                              child: TextField(
                                controller: emailCtrl,
                                focusNode: emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.done,
                                onSubmitted: submitting
                                    ? null
                                    : (_) => sendReset(setLocal),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'correo@gmail.com',
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: orange,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: submitting
                                        ? null
                                        : () => Navigator.pop(ctx),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: orange,
                                      side: BorderSide(
                                        color: orange.withValues(alpha: 0.55),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancelar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _HoverScale(
                                    enabled: !submitting,
                                    child: SizedBox(
                                      height: 48,
                                      child: FilledButton(
                                        onPressed: submitting
                                            ? null
                                            : () => sendReset(setLocal),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                        child: Ink(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [orange, orange2],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Container(
                                            alignment: Alignment.center,
                                            child: submitting
                                                ? const SizedBox(
                                                    height: 18,
                                                    width: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : const Text(
                                                    'Enviar enlace',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
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
          },
        );
      },
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

    emailCtrl.dispose();
    emailFocus.dispose();
  }

  Future<void> _showStatusPopup({
    required bool ok,
    required String title,
    required String message,
    required Color accent,
    bool gradient = false,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'status',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder:
          (BuildContext context, Animation<double> _, Animation<double> __) {
            return _StatusPopup(
              ok: ok,
              title: title,
              message: message,
              accent: accent,
              gradient: gradient,
            );
          },
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

  Widget _roleChips() {
    final green = AppTheme.pepperGreen;
    final red = AppTheme.pepperRed;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _HoverScale(
          enabled: !_loading,
          child: ChoiceChip(
            selected: _role == UserRole.monitora,
            label: const Text('Monitores'),
            onSelected: _loading
                ? null
                : (_) => setState(() => _role = UserRole.monitora),
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            selectedColor: green.withValues(alpha: 0.16),
            side: BorderSide(
              color: (_role == UserRole.monitora)
                  ? green.withValues(alpha: 0.60)
                  : Colors.black.withValues(alpha: 0.18),
              width: (_role == UserRole.monitora) ? 1.4 : 1.1,
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w900,
              color: (_role == UserRole.monitora)
                  ? green
                  : Colors.black.withValues(alpha: 0.70),
            ),
            showCheckmark: true,
            checkmarkColor: green,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(width: 10),
        _HoverScale(
          enabled: !_loading,
          child: ChoiceChip(
            selected: _role == UserRole.admin,
            label: const Text('Administrativos'),
            onSelected: _loading
                ? null
                : (_) => setState(() => _role = UserRole.admin),
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            selectedColor: red.withValues(alpha: 0.16),
            side: BorderSide(
              color: (_role == UserRole.admin)
                  ? red.withValues(alpha: 0.60)
                  : Colors.black.withValues(alpha: 0.18),
              width: (_role == UserRole.admin) ? 1.4 : 1.1,
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w900,
              color: (_role == UserRole.admin)
                  ? red
                  : Colors.black.withValues(alpha: 0.70),
            ),
            showCheckmark: true,
            checkmarkColor: red,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallbackBg = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_accent.withValues(alpha: 0.12), Colors.white, Colors.white],
        ),
      ),
    );

    final slideOffset = _keyboardOpen ? const Offset(0, -0.12) : Offset.zero;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(child: fallbackBg),
                  Positioned.fill(
                    child: Image.asset(
                      _bgAsset,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: AnimatedSlide(
              offset: slideOffset,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: FadeTransition(
                            opacity: _fade,
                            child: SlideTransition(
                              position: _slide,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 14),
                                  _LogoCard(
                                    color: _accent,
                                    assetPath: _logoAsset,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'MONITOREO GEOPÓNICA',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Monitoreo fitosanitario de cultivos de pimiento',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: _accent.withValues(
                                            alpha: 0.88,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  _roleChips(),
                                  const SizedBox(height: 14),
                                  Card(
                                    elevation: 0,
                                    shadowColor: Colors.black.withValues(
                                      alpha: 0.12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                      side: BorderSide(
                                        color: Colors.black.withValues(
                                          alpha: 0.07,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Form(
                                        key: _formKey,
                                        child: Column(
                                          children: [
                                            _FancyField(
                                              controller: _userCtrl,
                                              focusNode: _emailFocus,
                                              enabled: !_loading,
                                              accent: _accent,
                                              label: 'Correo Gmail',
                                              hint: 'ejemplo@gmail.com',
                                              prefixIcon: Icons.email_outlined,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              textInputAction:
                                                  TextInputAction.next,
                                              validator: (v) {
                                                final s = (v ?? '')
                                                    .trim()
                                                    .toLowerCase();
                                                if (s.isEmpty) {
                                                  return 'Ingresa tu correo';
                                                }
                                                if (!s.endsWith('@gmail.com')) {
                                                  return 'Debe ser un correo @gmail.com';
                                                }
                                                return null;
                                              },
                                              onSubmitted: (_) =>
                                                  _passFocus.requestFocus(),
                                            ),
                                            const SizedBox(height: 12),
                                            _FancyField(
                                              controller: _passCtrl,
                                              focusNode: _passFocus,
                                              enabled: !_loading,
                                              accent: _accent,
                                              label: 'Contraseña',
                                              hint: '••••••••',
                                              prefixIcon:
                                                  Icons.lock_outline_rounded,
                                              obscureText: _obscure,
                                              textInputAction:
                                                  TextInputAction.done,
                                              validator: (v) {
                                                final s = (v ?? '');
                                                if (s.isEmpty) {
                                                  return 'Ingresa tu contraseña';
                                                }
                                                if (s.length < 6) {
                                                  return 'Contraseña muy corta';
                                                }
                                                return null;
                                              },
                                              suffix: IconButton(
                                                onPressed: _loading
                                                    ? null
                                                    : () => setState(
                                                        () => _obscure =
                                                            !_obscure,
                                                      ),
                                                icon: Icon(
                                                  _obscure
                                                      ? Icons.visibility
                                                      : Icons.visibility_off,
                                                ),
                                                color: _accent,
                                              ),
                                              onSubmitted: (_) => _submit(),
                                            ),
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.03,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.08),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.lock_clock_outlined,
                                                    color: _accent,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Expanded(
                                                    child: Text(
                                                      'Mantener sesión activa',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                  Switch(
                                                    value: _rememberMe,
                                                    onChanged: _loading
                                                        ? null
                                                        : (v) async {
                                                            setState(
                                                              () =>
                                                                  _rememberMe =
                                                                      v,
                                                            );
                                                            await _saveRememberPreference();
                                                            await _applyAuthPersistence();
                                                          },

                                                    // ✅ Depende del rol (verde monitora / rojo admin)
                                                    thumbColor:
                                                        WidgetStateProperty.resolveWith<
                                                          Color?
                                                        >((states) {
                                                          if (states.contains(
                                                            WidgetState
                                                                .disabled,
                                                          )) {
                                                            return Colors.black
                                                                .withValues(
                                                                  alpha: 0.25,
                                                                );
                                                          }
                                                          if (states.contains(
                                                            WidgetState
                                                                .selected,
                                                          )) {
                                                            return _accent; // ON
                                                          }
                                                          return Colors
                                                              .white; // OFF
                                                        }),
                                                    trackColor:
                                                        WidgetStateProperty.resolveWith<
                                                          Color?
                                                        >((states) {
                                                          if (states.contains(
                                                            WidgetState
                                                                .disabled,
                                                          )) {
                                                            return Colors.black
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                );
                                                          }
                                                          if (states.contains(
                                                            WidgetState
                                                                .selected,
                                                          )) {
                                                            return _accent
                                                                .withValues(
                                                                  alpha: 0.35,
                                                                ); // ON track
                                                          }
                                                          return Colors.black
                                                              .withValues(
                                                                alpha: 0.20,
                                                              ); // OFF track
                                                        }),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            _HoverScale(
                                              enabled: !_loading,
                                              child: SizedBox(
                                                width: double.infinity,
                                                height: 48,
                                                child: FilledButton(
                                                  onPressed: _loading
                                                      ? null
                                                      : _submit,
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: _accent,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                  ),
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                      milliseconds: 160,
                                                    ),
                                                    child: _loading
                                                        ? const SizedBox(
                                                            key: ValueKey(
                                                              'loading',
                                                            ),
                                                            height: 20,
                                                            width: 20,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          )
                                                        : Text(
                                                            'Entrar como $_roleLabel',
                                                            key: const ValueKey(
                                                              'text',
                                                            ),
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                ),
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            _HoverUnderlineLink(
                                              enabled: !_loading,
                                              color: _orange,
                                              onTap: _loading
                                                  ? null
                                                  : _showForgotPasswordDialog,
                                              child: const Text(
                                                '¿Olvidaste tu contraseña?',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    '© 2026 Geopónica. Todos los derechos reservados.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.black.withValues(
                                            alpha: 0.70,
                                          ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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

class _LogoCard extends StatelessWidget {
  final Color color;
  final String assetPath;

  const _LogoCard({required this.color, required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          placeholderBuilder: (_) =>
              Icon(Icons.eco_outlined, color: color, size: 42),
        ),
      ),
    );
  }
}

/// Campo “pro”: borde/halo al focus + look limpio (aislado del Theme global)
class _FancyField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  final Color accent;
  final String label;
  final String hint;
  final IconData prefixIcon;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  final bool obscureText;
  final Widget? suffix;

  const _FancyField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.accent,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.obscureText = false,
    this.suffix,
  });

  // Neutros
  static const Color _labelColor = Color(0xFF4A4A4A);
  static const Color _hintColor = Color(0xFF8A8A8A);
  static const Color _textColor = Color(0xFF222222);

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused
              ? accent.withValues(alpha: 0.60)
              : Colors.black.withValues(alpha: 0.10),
          width: focused ? 1.4 : 1.0,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: Theme(
        // ✅ Aísla este TextFormField del InputDecorationTheme global
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 12),
          ),
        ),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          validator: validator,

          style: const TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w700,
          ),
          cursorColor: accent,

          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(
              color: _labelColor,
              fontWeight: FontWeight.w800,
            ),
            floatingLabelStyle: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
            ),
            hintStyle: const TextStyle(
              color: _hintColor,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(prefixIcon, color: accent),
            suffixIcon: suffix == null
                ? null
                : IconTheme(
                    data: IconThemeData(color: accent),
                    child: suffix!,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Hover scale (web/desktop) + pressed feel
class _HoverScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const _HoverScale({required this.child, this.enabled = true});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;
  bool _down = false;

  bool get _canHover {
    return kIsWeb ||
        (!defaultTargetPlatform.toString().contains('android') &&
            !defaultTargetPlatform.toString().contains('iOS'));
  }

  @override
  Widget build(BuildContext context) {
    final scale = !widget.enabled
        ? 1.0
        : (_down ? 0.985 : (_hover ? 1.03 : 1.0));

    return MouseRegion(
      onEnter: (_) =>
          _canHover && widget.enabled ? setState(() => _hover = true) : null,
      onExit: (_) =>
          _canHover && widget.enabled ? setState(() => _hover = false) : null,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _down = false)
            : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Link con underline animado (bonito) + hover
class _HoverUnderlineLink extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final bool enabled;

  const _HoverUnderlineLink({
    required this.child,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_HoverUnderlineLink> createState() => _HoverUnderlineLinkState();
}

class _HoverUnderlineLinkState extends State<_HoverUnderlineLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;

    return MouseRegion(
      onEnter: (_) => widget.enabled ? setState(() => _hover = true) : null,
      onExit: (_) => widget.enabled ? setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle(
              style: TextStyle(color: c),
              child: widget.child,
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              height: 2,
              width: _hover ? 180 : 0,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// POPUP (✅ / ❌ con animación) tema naranja (degradado opcional)
class _StatusPopup extends StatefulWidget {
  final bool ok;
  final String title;
  final String message;
  final Color accent;
  final bool gradient;

  const _StatusPopup({
    required this.ok,
    required this.title,
    required this.message,
    required this.accent,
    required this.gradient,
  });

  @override
  State<_StatusPopup> createState() => _StatusPopupState();
}

class _StatusPopupState extends State<_StatusPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.ok ? Icons.check_circle_rounded : Icons.cancel_rounded;

    final orange = widget.accent;
    final orange2 = const Color(0xFFFF3D00);

    final header = Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.gradient
            ? LinearGradient(colors: [orange, orange2])
            : null,
        color: widget.gradient ? null : orange,
      ),
      child: Icon(icon, color: Colors.white, size: 54),
    );

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final dx = widget.ok ? 0.0 : _shake.value;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                elevation: 14,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(scale: _scale, child: header),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [orange, orange2],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Text(
                                'OK',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ),
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
