import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'services/offline/offline_sync_service.dart';

import 'routes/app_routes.dart';
import 'routes/routes_names.dart';

import 'widgets/loading_pepper_screen.dart';

// ✅ IMPORTA TU TEMA
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Hive.initFlutter();
  await OfflineSyncService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ AQUÍ SE QUITA EL MORADO EN TODA LA APP
      theme: AppTheme.light(),

      // (opcional) si NO quieres dark mode nunca:
      themeMode: ThemeMode.light,

      // ✅ Router central
      onGenerateRoute: AppRoutes.onGenerateRoute,

      // ✅ Arranca en el Gate real
      initialRoute: RouteNames.authGate,
    );
  }
}

/// ✅ Gate: muestra loading mínimo 13s y luego decide ruta por Auth + Firestore.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const Duration _minSplash = Duration(seconds: 13);

  late final Future<void> _minDelayFuture;
  StreamSubscription<User?>? _sub;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _minDelayFuture = Future<void>.delayed(_minSplash);

    _sub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _minDelayFuture;

      if (!mounted || _navigated) return;

      if (user == null) {
        _go(RouteNames.login);
        return;
      }

      try {
        final doc = await FirebaseFirestore.instance
            .collection('app_users')
            .doc(user.uid)
            .get();

        final data = doc.data();

        if (!doc.exists || data == null) {
          await FirebaseAuth.instance.signOut();
          _go(RouteNames.login);
          return;
        }

        final role = (data['role'] ?? '').toString().toLowerCase();
        final active = (data['active'] ?? false) == true;

        if (!active) {
          await FirebaseAuth.instance.signOut();
          _go(RouteNames.login);
          return;
        }

        if (role == 'admin') {
          if (!user.emailVerified) {
            await FirebaseAuth.instance.signOut();
            _go(RouteNames.login);
            return;
          }
          _go(RouteNames.homeAdmin);
          return;
        }

        if (role == 'monitora') {
          _go(RouteNames.homeMonitora);
          return;
        }

        await FirebaseAuth.instance.signOut();
        _go(RouteNames.login);
      } catch (_) {
        await FirebaseAuth.instance.signOut();
        _go(RouteNames.login);
      }
    });
  }

  void _go(String route) {
    if (_navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const _GateLoading();
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: LoadingPepperScreen(assetPath: 'assets/icons/pimiento.svg'),
    );
  }
}
