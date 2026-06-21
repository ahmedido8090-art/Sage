import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/login_screen.dart';
import 'theme/bella_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('users');
  await Hive.openBox('userDetails');
  runApp(const BellaApp());
}

class BellaApp extends StatelessWidget {
  const BellaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bella',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: BellaTheme.darkTheme,
      darkTheme: BellaTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      locale: const Locale('en'),
      home: const LoginScreen(),
    );
  }
}
