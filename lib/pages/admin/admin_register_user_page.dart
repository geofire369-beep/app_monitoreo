// lib/pages/admin/admin_register_user_page.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';

enum NewUserRole { monitora, admin }

class AdminRegisterUserPage extends StatefulWidget {
  const AdminRegisterUserPage({super.key});

  @override
  State<AdminRegisterUserPage> createState() => _AdminRegisterUserPageState();
}

class _AdminRegisterUserPageState extends State<AdminRegisterUserPage> {
  static const String _registerKey = 'admingeo123';

  bool _unlocked = false;
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;

  NewUserRole _role = NewUserRole.monitora;
  bool _active = true;

  // ✅ Reglas de contraseña
  bool _showChecklist = false;
  bool _hasLetter = false;
  bool _hasUpper = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _hasMinLength = false;
  bool _hasNoSpaces = false;
  bool _passwordsMatch = false;

  // ✅ FILTROS
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _roleFilter = 'all'; // all | monitora | admin

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askKey());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ================== THEME LOCAL (FORZAR ROJO, SIN MORADO) ==================
  ThemeData _adminTheme(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.pepperRed;

    final cs = base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      tertiary: accent,
      outline: Colors.black.withValues(alpha: 0.14),
    );

    final inputBase = base.inputDecorationTheme;

    OutlineInputBorder border(Color c, {double w = 1.0}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      colorScheme: cs,
      primaryColor: accent,

      // ✅ Evita subrayado/label morado en inputs
      inputDecorationTheme: inputBase.copyWith(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
        labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.78), fontWeight: FontWeight.w700),
        floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w800),
        prefixIconColor: accent,
        suffixIconColor: accent,
        enabledBorder: border(Colors.black.withValues(alpha: 0.12)),
        border: border(Colors.black.withValues(alpha: 0.12)),
        focusedBorder: border(accent.withValues(alpha: 0.85), w: 1.5),
        errorBorder: border(AppTheme.pepperRed.withValues(alpha: 0.70), w: 1.2),
        focusedErrorBorder: border(AppTheme.pepperRed, w: 1.5),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.22),
        selectionHandleColor: accent,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => accent),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.20),
        ),
      ),
    );
  }

  // ================== LOGS ==================
  void _log(String msg) {
    if (kDebugMode) debugPrint('[REGISTER] $msg');
  }

  void _logError(Object e, [StackTrace? st]) {
    if (kDebugMode) {
      debugPrint('[REGISTER][ERROR] $e');
      if (st != null) debugPrint(st.toString());
    }
  }

  // ================== POPUP (✅ / ❌) ==================
  Future<void> _showStatusPopup({
    required bool ok,
    required String title,
    required String message,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'status',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => _StatusPopup(ok: ok, title: title, message: message),
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

  // ================== CLAVE ADMIN ==================
  Future<void> _askKey() async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'register_key',
      barrierColor: Colors.black.withValues(alpha: 0.60),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) => _RegisterKeyDialog(
        registerKey: _registerKey,
        accent: AppTheme.pepperRed,
      ),
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

    if (!mounted) return;

    if (ok == true) {
      setState(() => _unlocked = true);
      HapticFeedback.lightImpact();
      await _showStatusPopup(
        ok: true,
        title: 'Acceso autorizado',
        message: 'Puedes dar de alta usuarios.',
      );
    } else {
      HapticFeedback.heavyImpact();
      await _showStatusPopup(
        ok: false,
        title: 'Acceso denegado',
        message: 'Clave incorrecta o acción cancelada.',
      );
      if (mounted) Navigator.pop(context);
    }
  }

  // ================== VALIDACIONES ==================
  String? _validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Ingresa el nombre';
    if (s.length < 2) return 'Nombre muy corto';
    return null;
  }

  String? _validateLast(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Ingresa apellidos';
    if (s.length < 2) return 'Apellidos muy cortos';
    return null;
  }

  String? _validateGmail(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'Ingresa el correo';
    if (!s.contains('@') || !s.contains('.')) return 'Correo inválido';
    if (!s.endsWith('@gmail.com')) return 'Debe ser un correo @gmail.com';
    return null;
  }

  void _onPasswordChanged(String value) {
    final prev = _validChecksCount;
    setState(() {
      _showChecklist = value.isNotEmpty;
      _hasLetter = RegExp(r'[a-zA-Z]').hasMatch(value);
      _hasUpper = RegExp(r'[A-Z]').hasMatch(value);
      _hasNumber = RegExp(r'[0-9]').hasMatch(value);
      _hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(value);
      _hasMinLength = value.length >= 8;
      _hasNoSpaces = !value.contains(' ');
      _passwordsMatch = _confirmCtrl.text.isNotEmpty && value == _confirmCtrl.text;
    });

    final now = _validChecksCount;
    if (now > prev) HapticFeedback.lightImpact();
  }

  void _onConfirmChanged(String value) {
    final prev = _validChecksCount;
    setState(() {
      _passwordsMatch = value.isNotEmpty && value == _passCtrl.text;
    });
    final now = _validChecksCount;
    if (now > prev) HapticFeedback.lightImpact();
  }

  int get _validChecksCount => [
        _hasLetter,
        _hasUpper,
        _hasNumber,
        _hasSpecial,
        _hasMinLength,
        _hasNoSpaces,
        _passwordsMatch,
      ].where((v) => v).length;

  String? _validatePasswordPolicy(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return 'Ingresa una contraseña';
    if (!_hasMinLength || !_hasLetter || !_hasUpper || !_hasNumber || !_hasSpecial || !_hasNoSpaces) {
      return 'No cumple requisitos';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return 'Confirma la contraseña';
    if (s != _passCtrl.text) return 'No coincide';
    return null;
  }

  // ================== UI: CHECKLIST ==================
  Widget _reqRow(bool ok, String text) {
    if (!ok) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) => Opacity(
        opacity: scale.clamp(0.0, 1.0),
        child: Transform.scale(scale: scale, alignment: Alignment.centerLeft, child: child),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.green))),
        ],
      ),
    );
  }

  Widget _buildChecklistCard() {
    if (!_showChecklist) return const SizedBox.shrink();

    final missing = <String>[];
    if (!_hasLetter) missing.add('una letra');
    if (!_hasUpper) missing.add('una mayúscula');
    if (!_hasNumber) missing.add('un número');
    if (!_hasSpecial) missing.add('un carácter especial');
    if (!_hasMinLength) missing.add('mínimo 8 caracteres');
    if (!_hasNoSpaces) missing.add('sin espacios');
    if (!_passwordsMatch) missing.add('que coincidan');

    final missingText = missing.isNotEmpty ? 'Te falta: ${missing.join(', ')}.' : null;
    final accent = AppTheme.pepperRed;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.14)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Requisitos de contraseña', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _reqRow(_hasLetter, 'Al menos una letra'),
            const SizedBox(height: 4),
            _reqRow(_hasUpper, 'Al menos una mayúscula'),
            const SizedBox(height: 4),
            _reqRow(_hasNumber, 'Al menos un número'),
            const SizedBox(height: 4),
            _reqRow(_hasSpecial, 'Al menos un carácter especial'),
            const SizedBox(height: 4),
            _reqRow(_hasMinLength, 'Mínimo 8 caracteres'),
            const SizedBox(height: 4),
            _reqRow(_hasNoSpaces, 'Sin espacios'),
            const SizedBox(height: 4),
            _reqRow(_passwordsMatch, 'Las contraseñas coinciden'),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: (missingText != null)
                  ? Text(
                      missingText,
                      key: const ValueKey('missing'),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const SizedBox(key: ValueKey('ok')),
            ),
          ],
        ),
      ),
    );
  }

  // ================== CREAR USUARIO (Auth secondary + Firestore) ==================
  Future<String> _createAuthUserSecondary({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final primary = Firebase.app();
    final secondary = await Firebase.initializeApp(
      name: 'secondary-${DateTime.now().millisecondsSinceEpoch}',
      options: primary.options,
    );

    try {
      final a = FirebaseAuth.instanceFor(app: secondary);

      _log('Creating Auth user (secondary) ... email=$email');
      final cred = await a.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      await cred.user?.updateDisplayName(displayName.trim());

      try {
        await cred.user?.sendEmailVerification();
        _log('Email verification sent.');
      } catch (e) {
        _log('Could not send verification: $e');
      }

      final uid = cred.user!.uid;
      await a.signOut();
      return uid;
    } finally {
      await secondary.delete();
    }
  }

  Future<void> _createUser() async {
    FocusScope.of(context).unfocus();
    if (!_unlocked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    final adminUid = AuthService().currentUid;
    if (adminUid == null) {
      setState(() => _loading = false);
      HapticFeedback.heavyImpact();
      await _showStatusPopup(ok: false, title: 'Sin sesión', message: 'No hay sesión activa.');
      return;
    }

    final name = _nameCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;

    final fullName = '$name $last'.trim();

    try {
      _log('START create user: $fullName <$email> role=$_role active=$_active');

      final uid = await _createAuthUserSecondary(
        email: email,
        password: password,
        displayName: fullName,
      );

      _log('Writing Firestore profile app_users/$uid ...');
      await FirebaseFirestore.instance.collection('app_users').doc(uid).set({
        'name': name,
        'lastName': last,
        'fullName': fullName,
        'email': email,
        'role': _role == NewUserRole.admin ? 'admin' : 'monitora',
        'active': _active,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
      });

      HapticFeedback.mediumImpact();
      if (!mounted) return;

      await _showStatusPopup(
        ok: true,
        title: 'Usuario creado',
        message: 'Se creó correctamente.\nSe envió verificación a:\n$email',
      );

      _nameCtrl.clear();
      _lastCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      _confirmCtrl.clear();

      setState(() {
        _role = NewUserRole.monitora;
        _active = true;

        _showChecklist = false;
        _hasLetter = false;
        _hasUpper = false;
        _hasNumber = false;
        _hasSpecial = false;
        _hasMinLength = false;
        _hasNoSpaces = false;
        _passwordsMatch = false;
      });
    } on FirebaseAuthException catch (e, st) {
      _logError(e, st);

      final msg = switch (e.code) {
        'email-already-in-use' => 'Ese correo ya está registrado.',
        'invalid-email' => 'Correo inválido.',
        'weak-password' => 'Contraseña muy débil.',
        'operation-not-allowed' => 'Activa Email/Password en Firebase Auth.',
        _ => e.message ?? 'Error de Auth: ${e.code}',
      };

      HapticFeedback.heavyImpact();
      if (mounted) await _showStatusPopup(ok: false, title: 'No se pudo crear', message: msg);
    } on FirebaseException catch (e, st) {
      _logError(e, st);

      final msg = (e.code == 'permission-denied')
          ? 'Sin permisos para escribir en Firestore (rules).'
          : (e.message ?? 'Error Firebase: ${e.code}');

      HapticFeedback.heavyImpact();
      if (mounted) await _showStatusPopup(ok: false, title: 'No se pudo guardar', message: msg);
    } catch (e, st) {
      _logError(e, st);
      HapticFeedback.heavyImpact();
      if (mounted) await _showStatusPopup(ok: false, title: 'Error', message: '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ================== LISTA / STREAM ==================
  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return FirebaseFirestore.instance.collection('app_users').orderBy('role').orderBy('fullName').snapshots();
  }

  // ================== DELETE ==================
  Future<void> _confirmDeleteDoc({required String uid, required String name}) async {
    final accent = AppTheme.pepperRed;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accent),
            const SizedBox(width: 8),
            const Text('Eliminar registro'),
          ],
        ),
        content: Text('¿Eliminar el perfil de este usuario?\n\n$name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('app_users').doc(uid).delete();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: true, title: 'Eliminado', message: 'Se eliminó el perfil.');
    } on FirebaseException catch (e, st) {
      _logError(e, st);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: false, title: 'No se pudo eliminar', message: e.message ?? e.code);
    } catch (e, st) {
      _logError(e, st);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: false, title: 'Error', message: '$e');
    }
  }

  // ================== EDIT ==================
  Future<void> _editUserDialog({required String uid, required Map<String, dynamic> data}) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final lastCtrl = TextEditingController(text: (data['lastName'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (data['email'] ?? '').toString());

    var role = (data['role'] ?? 'monitora').toString().toLowerCase();
    var active = (data['active'] ?? true) == true;

    final accent = AppTheme.pepperRed;

    final displayName =
        (data['fullName'] ?? '${data['name'] ?? ''} ${data['lastName'] ?? ''}').toString().trim();
    final headerName = displayName.isEmpty ? 'Editar usuario' : displayName;

    final saved = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'edit_user',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return Theme(
          data: _adminTheme(context),
          child: StatefulBuilder(
            builder: (ctx, setLocal) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: Colors.transparent,
                  child: Card(
                    elevation: 18,
                    shadowColor: Colors.black.withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: accent.withValues(alpha: 0.16)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(Icons.edit_rounded, color: accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        headerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Actualiza los datos del usuario',
                                        style: TextStyle(color: Colors.black.withValues(alpha: 0.62), fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
                                  onPressed: () => Navigator.pop(ctx, false),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: nameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre(s)',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: lastCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Apellidos',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Correo',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: role,
                                          decoration: const InputDecoration(
                                            labelText: 'Tipo',
                                            prefixIcon: Icon(Icons.security_outlined),
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'monitora', child: Text('Monitora')),
                                            DropdownMenuItem(value: 'admin', child: Text('Administrativo')),
                                          ],
                                          onChanged: (v) => setLocal(() => role = v ?? 'monitora'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                                            color: Colors.black.withValues(alpha: 0.03),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                active ? Icons.check_circle : Icons.cancel,
                                                size: 18,
                                                color: active ? AppTheme.pepperGreen : AppTheme.pepperRed,
                                              ),
                                              const SizedBox(width: 8),
                                              const Expanded(
                                                child: Text('Activo', style: TextStyle(fontWeight: FontWeight.w800)),
                                              ),
                                              Switch(
                                                value: active,
                                                onChanged: (v) => setLocal(() => active = v),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                                    ),
                                    child: Text(
                                      'Tip: El correo se guarda en minúsculas para evitar duplicados.',
                                      style: TextStyle(color: Colors.black.withValues(alpha: 0.70), fontSize: 12.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Guardar cambios'),
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
      },
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

    if (saved != true) {
      nameCtrl.dispose();
      lastCtrl.dispose();
      emailCtrl.dispose();
      return;
    }

    try {
      final n = nameCtrl.text.trim();
      final l = lastCtrl.text.trim();
      final e = emailCtrl.text.trim().toLowerCase();
      final full = ('$n $l').trim();

      await FirebaseFirestore.instance.collection('app_users').doc(uid).update({
        'name': n,
        'lastName': l,
        'fullName': full,
        'email': e,
        'role': role == 'admin' ? 'admin' : 'monitora',
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      HapticFeedback.lightImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: true, title: 'Actualizado', message: 'Cambios guardados.');
    } on FirebaseException catch (e, st) {
      _logError(e, st);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: false, title: 'No se pudo guardar', message: e.message ?? e.code);
    } catch (e, st) {
      _logError(e, st);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _showStatusPopup(ok: false, title: 'Error', message: '$e');
    } finally {
      nameCtrl.dispose();
      lastCtrl.dispose();
      emailCtrl.dispose();
    }
  }

  // ================== FILTROS ==================
  Widget _filtersBar() {
    final accent = AppTheme.pepperRed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 520),
          child: Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Buscar',
                    hintText: 'Nombre o correo',
                    prefixIcon: Icon(Icons.search_rounded, color: accent),
                    suffixIcon: (_searchCtrl.text.isEmpty)
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _roleFilter,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.security_outlined, color: accent),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(value: 'monitora', child: Text('Monitora')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrativo')),
                  ],
                  onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================== USERS CARD ==================
  Widget _usersTableCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pepperRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.pepperRed.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.pepperRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.group_rounded, color: AppTheme.pepperRed),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Usuarios registrados', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        SizedBox(height: 2),
                        Text('Monitores / Administrativos, estado y acciones.', style: TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _filtersBar(),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('Error: ${snap.error}'),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No hay registros todavía.',
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
                    ),
                  );
                }

                final q = _query.trim().toLowerCase();
                final filtered = docs.where((d) {
                  final data = d.data();
                  final role = (data['role'] ?? 'monitora').toString().toLowerCase();
                  final fullName =
                      (data['fullName'] ?? '${data['name'] ?? ''} ${data['lastName'] ?? ''}').toString().trim();
                  final email = (data['email'] ?? '').toString();

                  final roleOk = (_roleFilter == 'all') ? true : role == _roleFilter;
                  if (!roleOk) return false;

                  if (q.isEmpty) return true;

                  final hay = '${fullName.toLowerCase()} ${email.toLowerCase()} $role';
                  return hay.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Sin resultados con esos filtros.',
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cols = (w >= 1100) ? 3 : (w >= 760 ? 2 : 1);

                    if (cols == 1) {
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = filtered[i];
                          final data = d.data();
                          final uid = d.id;

                          final role = (data['role'] ?? 'monitora').toString().toLowerCase();
                          final fullName =
                              (data['fullName'] ?? '${data['name'] ?? ''} ${data['lastName'] ?? ''}').toString().trim();
                          final email = (data['email'] ?? '').toString();
                          final active = (data['active'] ?? true) == true;

                          return _UserRowCard(
                            role: role,
                            fullName: fullName.isEmpty ? '(Sin nombre)' : fullName,
                            email: email,
                            active: active,
                            onEdit: () => _editUserDialog(uid: uid, data: data),
                            onDelete: () => _confirmDeleteDoc(uid: uid, name: fullName.isEmpty ? email : fullName),
                          );
                        },
                      );
                    }

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: cols == 2 ? 2.35 : 2.55,
                      ),
                      itemBuilder: (_, i) {
                        final d = filtered[i];
                        final data = d.data();
                        final uid = d.id;

                        final role = (data['role'] ?? 'monitora').toString().toLowerCase();
                        final fullName =
                            (data['fullName'] ?? '${data['name'] ?? ''} ${data['lastName'] ?? ''}').toString().trim();
                        final email = (data['email'] ?? '').toString();
                        final active = (data['active'] ?? true) == true;

                        return _UserRowCard(
                          role: role,
                          fullName: fullName.isEmpty ? '(Sin nombre)' : fullName,
                          email: email,
                          active: active,
                          onEdit: () => _editUserDialog(uid: uid, data: data),
                          onDelete: () => _confirmDeleteDoc(uid: uid, name: fullName.isEmpty ? email : fullName),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================== REGISTER CARD ==================
  Widget _registerCard() {
    final accent = AppTheme.pepperRed;

    return Column(
      children: [
        _HeaderCard(accent: accent),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.14)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.person_add_alt_1, color: accent),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Alta de usuario', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              SizedBox(height: 2),
                              Text('Crea monitoras y administrativos.', style: TextStyle(fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre(s)',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lastCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Apellidos',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: _validateLast,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Gmail',
                      hintText: 'ejemplo@gmail.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: _validateGmail,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onChanged: _onPasswordChanged,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: _validatePasswordPolicy,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    onChanged: _onConfirmChanged,
                    decoration: InputDecoration(
                      labelText: 'Confirmar contraseña',
                      prefixIcon: const Icon(Icons.lock_reset_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: _validateConfirm,
                  ),
                  const SizedBox(height: 10),
                  _buildChecklistCard(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<NewUserRole>(
                          value: _role,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            prefixIcon: Icon(Icons.security_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: NewUserRole.monitora, child: Text('Monitora')),
                            DropdownMenuItem(value: NewUserRole.admin, child: Text('Administrativo')),
                          ],
                          onChanged: _loading ? null : (v) => setState(() => _role = v ?? NewUserRole.monitora),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                            color: Colors.black.withValues(alpha: 0.03),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _active ? Icons.check_circle : Icons.cancel,
                                size: 18,
                                color: _active ? AppTheme.pepperGreen : AppTheme.pepperRed,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Activo', style: TextStyle(fontWeight: FontWeight.w800))),
                              Switch(
                                value: _active,
                                onChanged: _loading ? null : (v) => setState(() => _active = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _createUser,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Crear usuario'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    if (!_unlocked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Theme(
      data: _adminTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Alta de usuarios'),
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            // ✅ FONDO: fondos.png (y no morado)
            Positioned.fill(
              child: Image.asset(
                'assets/images/fondos.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(color: Colors.white.withValues(alpha: 0.78)),
              ),
            ),

            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 980;

                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: SingleChildScrollView(child: _registerCard())),
                        const SizedBox(width: 14),
                        Expanded(flex: 6, child: SingleChildScrollView(child: _usersTableCard())),
                      ],
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _registerCard(),
                          const SizedBox(height: 14),
                          _usersTableCard(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            if (_loading)
              IgnorePointer(
                ignoring: true,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Color accent;
  const _HeaderCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.dashboard_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Panel Administrativo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    'Alta, edición y control de usuarios.',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.65), fontWeight: FontWeight.w600),
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

// ================== CARD POR USUARIO ==================
class _UserRowCard extends StatelessWidget {
  final String role; // 'admin' | 'monitora'
  final String fullName;
  final String email;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserRowCard({
    required this.role,
    required this.fullName,
    required this.email,
    required this.active,
    required this.onEdit,
    required this.onDelete,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    final first = parts.first.isNotEmpty ? parts.first[0] : 'U';
    final second = (parts.length >= 2 && parts[1].isNotEmpty) ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toLowerCase() == 'admin';
    final accent = isAdmin ? AppTheme.pepperRed : AppTheme.pepperGreen;
    final roleLabel = isAdmin ? 'Administrativo' : 'Monitora';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(fullName),
                        style: TextStyle(fontWeight: FontWeight.w900, color: accent),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.65),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (active ? AppTheme.pepperGreen : AppTheme.pepperRed).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (active ? AppTheme.pepperGreen : AppTheme.pepperRed).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: active ? AppTheme.pepperGreen : AppTheme.pepperRed,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            active ? 'Activo' : 'Inactivo',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: active ? AppTheme.pepperGreen : AppTheme.pepperRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAdmin ? Icons.admin_panel_settings_rounded : Icons.verified_user_rounded,
                          size: 16,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          roleLabel,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.2, color: accent),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_rounded, size: 18),
                    label: const Text('Eliminar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pepperRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================== POPUP (✅ / ❌) ==================
class _StatusPopup extends StatefulWidget {
  final bool ok;
  final String title;
  final String message;

  const _StatusPopup({
    required this.ok,
    required this.title,
    required this.message,
  });

  @override
  State<_StatusPopup> createState() => _StatusPopupState();
}

class _StatusPopupState extends State<_StatusPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
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
    final color = widget.ok ? AppTheme.pepperGreen : AppTheme.pepperRed;

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
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(scale: _scale, child: Icon(icon, color: color, size: 74)),
                      const SizedBox(height: 10),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.72)),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton(
                          // ✅ ya no usa morado
                          style: FilledButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
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

// ================== DIALOGO ROJO PERSONALIZADO (CLAVE) ==================
class _RegisterKeyDialog extends StatefulWidget {
  final String registerKey;
  final Color accent;

  const _RegisterKeyDialog({
    required this.registerKey,
    required this.accent,
  });

  @override
  State<_RegisterKeyDialog> createState() => _RegisterKeyDialogState();
}

class _RegisterKeyDialogState extends State<_RegisterKeyDialog> with SingleTickerProviderStateMixin {
  final _keyCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  bool _wrong = false;

  late final AnimationController _c;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final typed = _keyCtrl.text.trim();
    if (typed.isEmpty) {
      setState(() => _wrong = true);
      HapticFeedback.heavyImpact();
      _c.forward(from: 0);
      return;
    }

    setState(() {
      _submitting = true;
      _wrong = false;
    });

    if (typed == widget.registerKey) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _wrong = true;
      _submitting = false;
    });
    HapticFeedback.heavyImpact();
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Theme(
      // ✅ Forzar rojo y quitar morado del label/underline
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: accent),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: accent.withValues(alpha: 0.22),
          selectionHandleColor: accent,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Transform.translate(offset: Offset(_shake.value, 0), child: child),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 14,
                  shadowColor: Colors.black.withValues(alpha: 0.28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: accent.withValues(alpha: 0.22)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.lock_rounded, color: accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Clave de administrador',
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: accent),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Requerida para dar de alta usuarios',
                                      style: TextStyle(color: Colors.black.withValues(alpha: 0.62), fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _keyCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          onChanged: (_) => setState(() => _wrong = false),
                          cursorColor: accent, // ✅
                          decoration: InputDecoration(
                            labelText: 'Clave',
                            labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.72), fontWeight: FontWeight.w700),
                            floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w900), // ✅
                            prefixIcon: Icon(Icons.key_rounded, color: accent),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: accent, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.14)),
                            ),
                            errorText: _wrong ? 'Clave incorrecta' : null,
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : () => Navigator.pop(context, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _submitting ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Continuar', style: TextStyle(fontWeight: FontWeight.w900)),
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
      ),
    );
  }
}
