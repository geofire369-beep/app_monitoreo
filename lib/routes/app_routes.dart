import 'package:flutter/material.dart';

import '../routes/routes_names.dart';

// ✅ TU AuthGate (ya lo tienes)
import '../pages/auth_gate.dart';

// 🔥 Bootstrap (si lo sigues usando)
import '../pages/shared/bootstrap_page.dart';

// 🔐 Auth
import '../pages/login_page.dart';
import '../pages/forgot_password_page.dart';

// 🏠 Homes
import '../pages/monitora/monitora_home_page.dart';
import '../pages/admin/admin_home_page.dart';

// 🧑‍💼 Administrativo
import '../pages/admin/admin_register_user_page.dart';
import '../pages/admin/admin_mapas_page.dart';
import '../pages/admin/admin_monitoreo_page.dart';

// ✅ Admin: Agro / Reportes / Catálogos
import '../pages/admin/agro/agro_applications_page.dart';
import '../pages/admin/reports/reports_page.dart';
import '../pages/admin/catalogos/admin_catalogos_page.dart';

// 🗺️ Mapas
import '../pages/mapas/mapa_page.dart';

class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ✅ AuthGate (RAÍZ)
      case RouteNames.authGate:
        return _page(const AuthGate());

      // 🚀 Bootstrap (opcional)
      case RouteNames.bootstrap:
        return _page(const BootstrapPage());

      // 🔐 Auth
      case RouteNames.login:
        return _page(const LoginPage());

      case RouteNames.forgotPassword:
        return _page(const ForgotPasswordPage());

      // 🏠 Homes
      case RouteNames.homeAdmin:
        return _page(const HomeAdminPage());

      case RouteNames.homeMonitora:
        return _page(const HomeMonitoraPage());

      // 🧑‍💼 Administrativo
      case RouteNames.adminRegisterUser:
        return _page(const AdminRegisterUserPage());

      case RouteNames.adminMapas:
        return _page(const AdminMapasPage());

      case RouteNames.adminMonitoreoPage:
        return _page(const AdminMonitoreoPage());

      // ✅ Admin extra
      case RouteNames.adminAgroApplications:
        return _page(const AgroApplicationsPage());

      case RouteNames.adminReports:
        return _page(const ReportsPage());

      case RouteNames.adminCatalogos:
        return _page(const AdminCatalogosPage());

      // 🗺️ Mapas
      case RouteNames.mapaEditor:
        return _page(const MapaPage());

      // ❌ Ruta no encontrada
      default:
        return _page(
          Scaffold(
            body: Center(
              child: Text(
                'Ruta no encontrada:\n${settings.name}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
    }
  }

  static MaterialPageRoute _page(Widget page) {
    return MaterialPageRoute(builder: (_) => page);
  }
}
