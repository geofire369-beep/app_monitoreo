// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AuthService() {
    try {
      _auth.setLanguageCode('es');
    } catch (_) {}
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  String? get currentUid => _auth.currentUser?.uid;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async => _auth.signOut();
}
