
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'admin_page.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

/// ---------------------------------------------------------------
/// 1. BACKGROUND HANDLER
/// ---------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Notification: ${message.notification?.title}");
}

/// ---------------------------------------------------------------
/// 2. LOCAL NOTIFICATIONS
/// ---------------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// ---------------------------------------------------------------
/// 3. MAIN
/// ---------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("Firebase initialized");
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  // ── SAVE TOKEN LOCALLY ONLY (NO SERVER YET) ───────────────────
  final String? token = await messaging.getToken();
  if (token != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
    debugPrint('FCM token saved locally: $token');
  }

  // ── TOKEN REFRESH → UPLOAD ONLY IF LOGGED IN ─────────────────
  messaging.onTokenRefresh.listen((newToken) async {
    debugPrint('FCM token refreshed');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', newToken);

    final authToken = prefs.getString('authToken');
    if (authToken != null && authToken.isNotEmpty) {
      await _uploadTokenToServer(newToken, authToken);
    }
  });

  // ── BACKGROUND HANDLER
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── NOTIFICATION CHANNEL
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.max,
  );
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

  const AndroidInitializationSettings androidInit =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidInit),
  );

  // ── FOREGROUND
  FirebaseMessaging.onMessage.listen((msg) {
    final n = msg.notification;
    if (n == null) return;
    flutterLocalNotificationsPlugin.show(
      n.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  });

  // ── TAP & TERMINATED
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {
    debugPrint('Notification tapped: ${msg.notification?.title}');
  });
  final initMsg = await messaging.getInitialMessage();
  if (initMsg != null) {
    debugPrint('App opened via notification');
  }

  runApp(const MyApp());
}

/// ---------------------------------------------------------------
/// 4. UPLOAD TOKEN (USED BY login_screen.dart & refresh)
/// ---------------------------------------------------------------
Future<void> _uploadTokenToServer(String token, String authToken) async {
  try {
    final res = await ApiService.updateFcmToken(
      token: token,
      authToken: authToken,
    );
    debugPrint('Token uploaded: ${res.statusCode} ${res.body}');
  } catch (e) {
    debugPrint('Token upload failed: $e');
  }
}

/// ---------------------------------------------------------------
/// 5. MyApp & SplashScreen (unchanged)
/// ---------------------------------------------------------------
class CustomClampedTextScaler implements TextScaler {
  final TextScaler delegate;
  final double minScaleFactor;
  final double maxScaleFactor;

  const CustomClampedTextScaler(
    this.delegate, {
    required this.minScaleFactor,
    required this.maxScaleFactor,
  });

  @override
  double scale(double fontSize) {
    if (fontSize <= 0) return 0;
    final scaled = delegate.scale(fontSize);
    final factor = fontSize > 0 ? scaled / fontSize : 1.0;
    final clampedFactor = factor.clamp(minScaleFactor, maxScaleFactor);
    return fontSize * clampedFactor;
  }

  @override
  TextScaler clamp({double minScaleFactor = 0.0, double maxScaleFactor = double.infinity}) {
    return CustomClampedTextScaler(
      delegate,
      minScaleFactor: minScaleFactor,
      maxScaleFactor: maxScaleFactor,
    );
  }

  @override
  double get textScaleFactor {
    try {
      return delegate.textScaleFactor.clamp(minScaleFactor, maxScaleFactor);
    } catch (_) {
      return 1.0;
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELT_EMP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: Colors.white,
      ),
      builder: (context, child) {
        final mediaQueryData = MediaQueryData.fromView(View.of(context));
        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: CustomClampedTextScaler(
              mediaQueryData.textScaler,
              minScaleFactor: 1.0,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('authToken');
      final empName = prefs.getString('empName') ?? 'Employee';
      final empId = prefs.getString('empId') ?? '';
      final deviceSerial = prefs.getString('deviceSerialNumber') ?? '';
      final userRole = prefs.getString('userRole') ?? '';
      final companyId = prefs.getString('companyId') ?? ''; // ✅ ADD


      await Future.delayed(const Duration(seconds: 2));

      if (authToken != null && authToken.isNotEmpty) {
        final pendingCheckin = _parse(prefs, 'pendingCheckinRequests');
        final pendingCheckout = _parse(prefs, 'pendingCheckoutRequests');
        final pendingDevice = _parse(prefs, 'pendingDeviceRequests');
        final pendingLeave = _parse(prefs, 'pendingLeaveRequests');
        final isAdmin = userRole == 'admin' || empId == '0';

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => isAdmin
                ? AdminPage(
              empName: empName,
              pendingCheckinRequests: pendingCheckin,
              pendingCheckoutRequests: pendingCheckout,
              pendingDeviceRequests: pendingDevice,
              pendingLeaveRequests: pendingLeave,
            )
                : CheckInOutScreen(
              empName: empName,
              empId: empId,
              authToken: authToken,
              deviceSerialNumber: deviceSerial,
              companyId: companyId, // ✅ ADD

            ),
          ),
        );
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e, st) {
      debugPrint('Splash error: $e\n$st');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  List<Map<String, dynamic>> _parse(SharedPreferences prefs, String key) {
    final str = prefs.getString(key);
    if (str == null || str.isEmpty) return [];
    try {
      return (jsonDecode(str) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/eltrive_plan.png', height: 100, width: 100, fit: BoxFit.contain),
            const SizedBox(height: 20),
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
          ],
        ),
      ),
    );
  }
}