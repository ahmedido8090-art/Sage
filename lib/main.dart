// main.dart
//
// Changes vs original:
//  • `home` is now SplashScreen (which handles its own navigation to
//    Dashboard or Login after the branded intro animation).
//  • All other setup is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/wellness_screen.dart';
import 'services/user_service.dart';
import 'services/bella_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('users');
  await Hive.openBox('userDetails');
  await Hive.openBox('session');
  await BellaService.openBox();
  await ThemeController.load();
  await UserService().restoreSession();

  runApp(const SageApp());
}

class SageApp extends StatelessWidget {
  const SageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (context, isDark, _) {
        return MaterialApp(
          key: ValueKey(isDark),
          title: 'Sage Health',
          theme: isDark ? SageTheme.dark : SageTheme.light,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
          // Always start with the splash — it decides where to go next.
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
          navigatorObservers: [wellnessRouteObserver],
        );
      },
    );
  }
}