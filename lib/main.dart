import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
import 'screens/home_screen.dart';
import 'screens/enrollment_screen.dart';
import 'screens/user_list_screen.dart';
// import 'screens/matching_screen.dart'; // We will enable this later


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // This injects the AppStateProvider into the entire app
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
      ],
      child: MaterialApp(
        title: 'Morfin Auth',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F172A)),
          useMaterial3: true,
        ),
        // Start at the Home Screen
        home: HomeScreen(),

        // Define navigation routes
        routes: {
          '/enroll': (context) => EnrollmentScreen(),
          // '/match': (context) => MatchingScreen(), // Uncomment later
          '/users': (context) => UserListScreen(),
        },
      ),
    );
  }
}