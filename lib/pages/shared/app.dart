import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../routes/routes_names.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Estadías Geopónica',
      theme: AppTheme.light(),

      initialRoute: RouteNames.login,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
