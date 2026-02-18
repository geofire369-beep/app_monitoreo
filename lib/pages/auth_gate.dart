import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../routes/routes_names.dart';
import '../widgets/loading_pepper_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _minSplash = Duration(seconds: 13);

  late final Future<void> _minDelayFuture;
  StreamSubscription<User?>? _sub;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // 1) Forzar mínimo 13s de loading
    _minDelayFuture = Future<void>.delayed(_minSplash);

    // 2) Escuchar auth changes
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      // Espera a que pasen 13s mínimo
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
          // Si quieres forzar verificación
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

    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mientras decide + mientras corre el delay de 13s:
    return const LoadingPepperScreen(assetPath: 'assets/icons/pimiento.svg');
  }
}
