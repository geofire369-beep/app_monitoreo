class RouteNames {
  // ✅ Gate real (decide Login/Home sin brincos)
  static const String authGate = '/';

  // 🚀 Bootstrap / Splash (si lo usas aparte)
  static const String bootstrap = '/bootstrap';

  // 🔐 Auth
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';

  // 🏠 Homes
  static const String homeAdmin = '/home-admin';
  static const String homeMonitora = '/home-monitora';

  // 🧑‍💼 Administrativo
  static const String adminRegisterUser = '/admin/register-user';
  static const String adminMonitoreoPage = '/admin/monitoreo-page';

  // ✅ Admin: Agro / Reportes / Catálogos
  static const String adminAgroApplications = '/admin/agro/applications';
  static const String adminReports = '/admin/reports';
  static const String adminCatalogos = '/admin/catalogos';

  // 🗺️ Mapas
  static const String mapaEditor = '/mapa-editor';
  static const String adminMapas = '/admin/mapas';

  // 👤 Perfil
  static const String profile = '/profile';
}
