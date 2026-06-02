// ──────────────────────────────────────────────────────────────
// login_screen.dart
// ──────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:android_id/android_id.dart';
import 'package:permission_handler/permission_handler.dart';

import 'admin_page.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

/// ── FCM TOKEN UPLOAD SERVICE ─────────────────────────────────
class FcmService {
  static Future<void> upload({
    required String fcmToken,
    required String authToken,
    required String empId,
    required String userId,
    required String companyId,

    String? deviceSerial,
  }) async {
    try {
      debugPrint('🔔 Uploading FCM token to server...');
      debugPrint('   - Token: ${fcmToken.substring(0, 20)}...');
      debugPrint('   - Auth Token: ${authToken.substring(0, 20)}...');
      debugPrint('   - Emp ID: $empId');
      debugPrint('   - Device Serial: $deviceSerial');

      final response = await ApiService.saveFcmToken(
        fcmToken: fcmToken,
        authToken: authToken,
        empId: empId,
        companyId: companyId,
        deviceSerial: deviceSerial,
      );

      debugPrint('🔔 FCM Upload Response: ${response.statusCode}');
      debugPrint('   - Body: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'success') {
          debugPrint('✅ FCM token saved to server successfully!');
        } else {
          debugPrint('❌ Server rejected token: ${json['message']}');
        }
      } else {
        debugPrint('❌ HTTP Error uploading FCM token: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Failed to upload FCM token: $e');
    }
  }
}

// ──────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final String initialUserId;
  final String initialPassword;

  const LoginScreen({
    super.key,
    this.initialUserId = '',
    this.initialPassword = '',
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController userIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;


  @override
  void initState() {
    super.initState();
    userIdController.text = widget.initialUserId;
    passwordController.text = widget.initialPassword;
    _requestPermissions();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUserId = prefs.getString('savedUserId') ?? '';
    final savedPassword = prefs.getString('savedPassword') ?? '';
    if (savedUserId.isNotEmpty && userIdController.text.isEmpty) {
      userIdController.text = savedUserId;
    }
    if (savedPassword.isNotEmpty && passwordController.text.isEmpty) {
      passwordController.text = savedPassword;
    }
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.location.request();
    debugPrint("Location permission: $status");
    if (status.isDenied) {
      _showSnack("Please grant location permission in settings.");
    }
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString("deviceSerialNumber") ?? "";
    if (stored.isNotEmpty && stored != "unknown_device_id") {
      return stored;
    }

    const max = 3;
    for (int i = 1; i <= max; i++) {
      try {
        final id = await const AndroidId().getId();
        if (id != null && id.isNotEmpty) {
          await prefs.setString("deviceSerialNumber", id);
          return id;
        }
      } catch (e) {
        debugPrint("AndroidId attempt $i failed: $e");
      }
      if (i < max) await Future.delayed(const Duration(milliseconds: 500));
    }
    return "unknown_device_id";
  }

  Future<Position?> getLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await _showGPSDialog();
      return null;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _showSnack("Location permission denied.");
        return null;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _showSnack("Location permanently denied – enable in settings.");
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
      return null;
    }
  }

  Future<void> _showGPSDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("GPS Disabled"),
        content: const Text("Please enable GPS to continue."),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text("Open Settings"),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ],
      ),
    );
  }

  Future<bool> hasInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // ── LOGIN ─────────────────────────────────────────────────────
  Future<void> login() async {
    final userId = userIdController.text.trim();
    final password = passwordController.text.trim();

    if (userId.isEmpty || password.isEmpty) {
      _showSnack("Please enter email and password");
      return;
    }

    if (!await hasInternetConnection()) {
      _showNoInternet();
      return;
    }

    setState(() => isLoading = true);

    try {
      final deviceId = await getDeviceId();
      debugPrint("📱 DEVICE SERIAL NUMBER: $deviceId");
      if (deviceId == "unknown_device_id") {
        _showSnack("Failed to get device ID. Restart the app.");
        return;
      }

      final pos = await getLocation();
      final lat = pos?.latitude.toString() ?? "0.0";
      final lng = pos?.longitude.toString() ?? "0.0";

      final prefs = await SharedPreferences.getInstance();
      final fcmToken = prefs.getString("fcm_token") ?? "";

      debugPrint("Sending login → fcm_token: $fcmToken");

      final response = await ApiService.login(
        userId: userId,
        password: password,
        deviceId: deviceId,
        latitude: lat,
        longitude: lng,
        fcmToken: fcmToken,
      );

      debugPrint("Login response ${response.statusCode}: ${response.body}");

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == "success") {
          final empName = json['emp_name'] ?? "Employee";
          final empId = json['emp_id']?.toString() ?? "";
          final authToken = json['auth_token'] ?? "";
          final companyId = json['company_id']?.toString() ?? ""; // ✅ ADD

          final role = json['user_role']?.toString() ?? (empId == "0" ? "admin" : "employee");

          debugPrint('🆔 Login success - Role: $role, Emp ID: $empId, Auth Token: ${authToken.substring(0, 20)}...');

          // Save login data
          await prefs.setString("savedUserId", userId);
          await prefs.setString("savedPassword", password);
          await prefs.setString("authToken", authToken);
          await prefs.setString("empName", empName);
          await prefs.setString("empId", empId);
          await prefs.setString("deviceSerialNumber", deviceId);
          await prefs.setString("userRole", role);
          await prefs.setString("companyId", companyId);

          // ── UPLOAD FCM TOKEN TO SERVER ───────────────────────
          if (fcmToken.isNotEmpty) {
            debugPrint('🔄 Starting FCM token upload for $role...');
            await FcmService.upload(
              fcmToken: fcmToken,
              authToken: authToken,
              empId: empId,
              userId: userId,
              deviceSerial: deviceId,
              companyId: companyId, // ✅ ADD

            );
          } else {
            debugPrint('⚠️ No FCM token available for upload');
          }

          // Navigate
          if (role == "admin") {
            debugPrint('👑 Navigating to Admin Page');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => AdminPage(
                  empName: empName,
                  pendingCheckinRequests: [],
                  pendingCheckoutRequests: [],
                  pendingDeviceRequests: [],
                  pendingLeaveRequests: [],
                ),
              ),
            );
          } else {
            debugPrint('👤 Navigating to Employee CheckInOut Screen');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CheckInOutScreen(
                  empName: empName,
                  empId: empId,
                  authToken: authToken,
                  deviceSerialNumber: deviceId,
                  companyId: companyId, // ✅ ADD

                ),
              ),
            );
          }
        } else {
          _showSnack(json['message'] ?? "Invalid credentials");
        }
      } else {
        _showSnack("Server error (${response.statusCode})");
      }
    } on TimeoutException {
      _showSnack("Request timed out");
    } on http.ClientException {
      _showSnack("Network error");
    } catch (e, st) {
      debugPrint("Login error: $e\n$st");
      _showSnack("Something went wrong");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showNoInternet() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No Internet"),
        content: const Text("Check your connection and try again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    userIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Image.asset('assets/eltrive_plan.png', height: 200, fit: BoxFit.contain),
          ),
          const SizedBox(height: 50),
          TextField(
            controller: userIdController,
            decoration: InputDecoration(
              labelText: "Email",
              labelStyle: const TextStyle(color: Colors.blue),
              filled: true,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: passwordController,
            obscureText: !isPasswordVisible,
            decoration: InputDecoration(
              labelText: "Password",
              labelStyle: const TextStyle(color: Colors.blue),
              filled: true,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(
                icon: Icon(
                  isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey[600],
                ),
                onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
              ),
            ),
          ),
          const SizedBox(height: 35),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text("Login", style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}