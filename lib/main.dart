import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/wellness_screen.dart';
import 'services/user_service.dart';
import 'band/band_monitor.dart';
import 'notifications/notification_service.dart';
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
  await UserService().migrateLegacyCredentials();
  await UserService().restoreSession();
  await BandMonitor.instance.start();
  await NotificationService.instance.init();
  NotificationService.instance.refresh();

  runApp(const SageApp());
}

class SageApp extends StatefulWidget {
  const SageApp({super.key});

  @override
  State<SageApp> createState() => _SageAppState();
}

class _SageAppState extends State<SageApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app is the moment today's progress is most likely to
  /// have changed, so re-plan the reminders around it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.instance.refreshPermission();
      NotificationService.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'Sage Health',
          theme: isDark ? SageTheme.dark : SageTheme.light,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
          // The splash decides whether to show login or the dashboard.
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
          navigatorObservers: [wellnessRouteObserver],
        );
      },
    );
  }
}
