import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

// Replace these with your actual import paths
import 'admin_page.dart';
import 'leave_screen.dart';
import 'login_screen.dart';
import 'main.dart';
import 'payslip_screen.dart';
import 'Requests.dart';
import 'expenses_screen.dart';
import 'more_screen.dart';
import 'emp_profile.dart';
import 'services/api_service.dart';

// Global notification plugin for foreground
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Workmanager task identifier
const String finalLocationTask = "sendFinalLocationTask";

// Add this near the top (global or in class)
int _backgroundLocationSendCount = 0; // optional - to show how many times sent

// ────────────────────────────────────────────────
// Inside callbackDispatcher()  →  Workmanager task
// ────────────────────────────────────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == finalLocationTask) {
      print('Workmanager task executed at ${DateTime.now().toIso8601String()}');

      try {
        final prefs = await SharedPreferences.getInstance();
        final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
        if (!isCheckedIn) {
          print('Not checked in → skipping');
          return true;
        }

        // ... (your existing location permission + get position code remains same)

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final payload = {
          'auth_token': inputData?['authToken'] ?? '',
          'emp_id': inputData?['empId'] ?? '',
          'shift_id': inputData?['shiftId'] ?? '',
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'device_serial_number': inputData?['deviceSerialNumber'] ?? '',
        };

        var connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult != ConnectivityResult.none) {
          final response = await ApiService.sendLocationUpdate(payload);

          final data = jsonDecode(response.body);
          print('Workmanager Response: $data');

          if (response.statusCode == 200 && data['status'] == 'ok') {
            // ──────────────── NEW: Show notification on every successful send ────────────────
            final bgPlugin = FlutterLocalNotificationsPlugin();
            await bgPlugin.initialize(
              const InitializationSettings(
                android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              ),
            );

            _backgroundLocationSendCount++; // optional counter

            String notificationBody = 'Location updated successfully in background';
            if (data['auto_checkout'] == true) {
              notificationBody =
              'Auto-checkout triggered!\nTotal hours: ${data['cumulative_working_hours'] ?? 'N/A'}';
              await prefs.setBool('is_checked_in', false);
              await Workmanager().cancelByUniqueName(finalLocationTask);
            } else {
              notificationBody =
              'Background location sent (${_backgroundLocationSendCount}x today)';
            }

            await bgPlugin.show(
              DateTime.now().millisecondsSinceEpoch % 10000, // unique id
              data['auto_checkout'] == true ? 'Auto Checkout' : 'Attendance Tracking',
              notificationBody,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'attendance_channel_id',
                  'Attendance Notifications',
                  channelDescription: 'Background location & attendance updates',
                  importance: Importance.defaultImportance,
                  priority: Priority.defaultPriority,
                  ticker: 'Location sent',
                ),
              ),
            );

            // ──────────────────────────────────────────────────────────────

            if (data['auto_checkout'] == true) {
              print('Auto-checkout done → stopping task');
              return true;
            }
            return true;
          } else {
            // your existing error handling...
            await _storePendingLocation(payload, prefs);
            return false;
          }
        } else {
          print('No internet → storing pending');
          await _storePendingLocation(payload, prefs);
          return false;
        }
      } catch (e) {
        print('Workmanager error: $e');
        // Silent error tracking in background - no notification spam
        return false;
      }
    }
    return true;
  });
}
Future<void> _storePendingLocation(
  Map<String, dynamic> payload,
  SharedPreferences prefs,
) async {
  final pendingLocations = prefs.getStringList('pending_locations') ?? [];
  pendingLocations.add(jsonEncode(payload));
  await prefs.setStringList('pending_locations', pendingLocations);
  print('Workmanager stored pending location: $payload');
}

class CheckInOutScreen extends StatefulWidget {
  final String empName;
  final String empId;
  final String authToken;
  final String deviceSerialNumber;
  final String companyId;
  final bool isAdmin;

  const CheckInOutScreen({
    super.key,
    required this.empName,
    required this.empId,
    required this.authToken,
    required this.deviceSerialNumber,
    required this.companyId, // ✅
    this.isAdmin = false,
  });

  @override
  State<CheckInOutScreen> createState() => _CheckInOutScreenState();
}

class _CheckInOutScreenState extends State<CheckInOutScreen>
    with WidgetsBindingObserver {
  late Timer clockTimer;
  Timer? workingTimer;
  Timer? locationSendTimer;
  bool isProcessingCheckIn = false;
  bool isProcessingCheckOut = false;
  String currentTime = '';
  String checkInTime = '--:--:--';
  String checkOutTime = '--:--:--';
  String totalWorkingHours = '00:00:00';
  bool isAllowedToCheckIn = true;
  bool isAllowedToCheckOut = false;
  bool isCheckedIn = false;
  Duration workingDuration = Duration.zero;
  DateTime? sessionStart;
  DateTime? _lastReminderDate;
  List<Map<String, dynamic>> empShifts = [];
  String? selectedShift;
  bool isShiftsLoading = true;
  bool isStatusLoading = false;
  bool isShiftSelectable = true;
  static const String _prefKeyCheckedIn = 'is_checked_in';
  static const String _prefKeyWorkingDuration = 'working_duration';
  static const String _prefKeyCheckInTime = 'check_in_time';
  static const String _prefKeyCheckOutTime = 'check_out_time';
  static const String _prefKeySessionStart = 'session_start';
  static const String _prefKeySelectedShift = 'selected_shift';
  static const String _prefKeyEmpId = 'empId';
  static const String _prefKeyPendingLocations = 'pending_locations';
  int _selectedIndex = 0;
  bool isProcessing = false;
  StreamSubscription<Position>? positionStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isConnected = true;
  bool _isNoInternetDialogShowing = false;
  bool isAdminUser = false;
  String _companyLogoUrl = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updateTime();
    clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => updateTime(),
    );
    _initNotifications();
    _initializeWorkmanager();
    _initializeConnectivityMonitoring();
    _loadShiftsAsync();
    _loadCompanyLogo();
  }

  Future<void> _loadCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final logo = prefs.getString("companyLogo") ?? "";
    if (logo.isNotEmpty && mounted) {
      setState(() => _companyLogoUrl = logo);
    }
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(settings);

    const AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
      'attendance_foreground',
      'Attendance Foreground Service',
      description: 'Permanent notification for active attendance tracking',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(foregroundChannel);

    // Request notification permission (Android 13+)
    await Permission.notification.request();
  }

  Future<void> _initializeWorkmanager() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    final prefs = await SharedPreferences.getInstance();
    final isCheckedIn = prefs.getBool(_prefKeyCheckedIn) ?? false;
    if (!isCheckedIn) {
      await Workmanager().cancelByUniqueName(finalLocationTask);
      print('Canceled stray Workmanager tasks on app start');
    }
  }

  void _initializeConnectivityMonitoring() {
    // Initial connectivity check
    _checkInternetConnectivity().then((isConnected) {
      setState(() {
        _isConnected = isConnected;
        if (!isConnected && !_isNoInternetDialogShowing) {
          _showNoInternetDialog();
        }
      });
    });

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      bool isConnected = await _checkInternetConnectivity();
      setState(() {
        _isConnected = isConnected;
      });
      if (!isConnected && !_isNoInternetDialogShowing) {
        _showNoInternetDialog();
      } else if (isConnected && _isNoInternetDialogShowing) {
        Navigator.of(
          context,
        ).pop(); // Close dialog when connectivity is restored
        _isNoInternetDialogShowing = false;
        // Retry critical operations
        await _loadShiftsAsync();
      }
    });
  }

  Future<bool> _checkInternetConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      return false;
    }
    try {
      final response = await ApiService.pingGoogle();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('AppLifecycleState changed: $state');
    if (state == AppLifecycleState.resumed) {
      print('App resumed. Auto-refreshing shifts and status...');
      _loadShiftsAsync();
    } else if (state == AppLifecycleState.detached && isCheckedIn) {
      _scheduleFinalLocationUpdate();
    } else if (state == AppLifecycleState.paused && isCheckedIn) {
      FlutterBackgroundService().invoke('updateState', {
        'isCheckedIn': isCheckedIn,
        'empId': widget.empId,
        'authToken': widget.authToken,
        'deviceSerialNumber': widget.deviceSerialNumber,
        'selectedShift': selectedShift,
      });
    }
  }

  Future<void> _scheduleFinalLocationUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!isCheckedIn) {
        await Workmanager().cancelByUniqueName(finalLocationTask);
        print('Canceled Workmanager task: User is not checked in');
        return;
      }

      // Cancel any existing task first
      await Workmanager().cancelByUniqueName(finalLocationTask);

      // Register new periodic task
      await Workmanager().registerPeriodicTask(
        finalLocationTask,
        finalLocationTask,
        frequency: const Duration(minutes: 15), // Android minimum reliable interval
        initialDelay: const Duration(seconds: 30), // Start soon after check-in/kill
        inputData: {
          'authToken': widget.authToken,
          'empId': widget.empId,
          'shiftId': selectedShift ?? '', // ← FIX: Prevent null → wrong type error
          'deviceSerialNumber': widget.deviceSerialNumber,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      print('Successfully scheduled Workmanager periodic task (every ~15 min)');
    } catch (e) {
      print('Failed to schedule Workmanager task: $e');
      _handleError('Background location scheduling failed', e);

      // Mark for retry on next app open
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('retry_final_location', true);
    }
  }
  Future<void> _requestBatteryOptimization() async {
    const String prefKeyBatteryPrompt = 'last_battery_optimization_prompt';
    final prefs = await SharedPreferences.getInstance();

    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      print('Battery optimization exemption already granted');
      return;
    }

    final lastPromptTimeStr = prefs.getString(prefKeyBatteryPrompt);
    final now = DateTime.now();
    final lastPromptTime =
        lastPromptTimeStr != null ? DateTime.parse(lastPromptTimeStr) : null;
    const promptInterval = Duration(days: 1);

    if (lastPromptTime == null ||
        now.difference(lastPromptTime) > promptInterval) {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please disable battery optimization for continuous location tracking.',
              ),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () async {
                  await Permission.ignoreBatteryOptimizations.request();
                  await prefs.setString(
                    prefKeyBatteryPrompt,
                    now.toIso8601String(),
                  );
                },
              ),
            ),
          );
        }
        print('Battery optimization exemption denied, prompted user');
        await Permission.ignoreBatteryOptimizations.request();
        await prefs.setString(prefKeyBatteryPrompt, now.toIso8601String());
      }
    } else {
      print(
        'Battery optimization prompt skipped (recently prompted at $lastPromptTimeStr)',
      );
    }
  }  void _autoSelectShift() {
    if (selectedShift != null && selectedShift!.isNotEmpty) {
      print('Auto-select: Shift already selected ($selectedShift), preserving user manual selection.');
      return;
    }

    if (empShifts.isEmpty) {
      print('Auto-select: empShifts is empty, cannot auto-select.');
      return;
    }

    final now = DateTime.now();
    final hour = now.hour;

    String targetShiftType = 'General';
    if (hour >= 5 && hour < 8) {
      targetShiftType = 'A';
    } else if (hour >= 8 && hour < 14) {
      bool hasGeneral = empShifts.any((s) {
        final name = s['name'].toString().toLowerCase();
        return name.contains('general') || name.contains('gen') || name.contains('day');
      });
      targetShiftType = hasGeneral ? 'General' : 'A';
    } else if (hour >= 14 && hour < 22) {
      targetShiftType = 'B';
    } else {
      targetShiftType = 'C';
    }

    Map<String, dynamic>? matchedShift;

    for (var shift in empShifts) {
      final name = shift['name'].toString().toLowerCase();
      if (targetShiftType == 'General' && (name.contains('general') || name.contains('gen') || name.contains('day'))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'A' && (name.contains('shift a') || name.contains('a shift') || name.startsWith('a ') || name.contains(': a') || name.contains(' a '))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'B' && (name.contains('shift b') || name.contains('b shift') || name.startsWith('b ') || name.contains(': b') || name.contains(' b '))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'C' && (name.contains('shift c') || name.contains('c shift') || name.startsWith('c ') || name.contains(': c') || name.contains(' c '))) {
        matchedShift = shift;
        break;
      }
    }

    if (matchedShift == null) {
      for (var shift in empShifts) {
        final name = shift['name'].toString().toLowerCase();
        if (targetShiftType == 'A' && name.contains('a')) {
          matchedShift = shift;
          break;
        } else if (targetShiftType == 'B' && name.contains('b')) {
          matchedShift = shift;
          break;
        } else if (targetShiftType == 'C' && name.contains('c')) {
          matchedShift = shift;
          break;
        }
      }
    }

    matchedShift ??= empShifts.first;

    setState(() {
      selectedShift = matchedShift!['id'];
    });
    print('Auto-detected and selected shift: ${matchedShift['name']} (ID: $selectedShift)');
  }

  Future<void> _loadShiftsAsync() async {
    try {
      setState(() => isShiftsLoading = true);
      await _initializeApp();
      if (!_isConnected) {
        if (mounted && !_isNoInternetDialogShowing) {
          _showNoInternetDialog();
        }
        setState(() => isShiftsLoading = false);
        return;
      }
      await _syncPendingLocations();
      setState(() => isShiftsLoading = false);
    } catch (e, stackTrace) {
      setState(() => isShiftsLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clockTimer?.cancel();
    workingTimer?.cancel();
    locationSendTimer?.cancel();
    positionStream?.cancel();
    _connectivitySubscription?.cancel();
    if (isCheckedIn) {
      _scheduleFinalLocationUpdate();
    }
    super.dispose();
  }

  Future<void> _checkAppUpdate() async {
    try {
      final response = await http.get(Uri.parse('https://hrm.eltrive.com/api/app-version')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = int.tryParse(data['latest_version_code']?.toString() ?? '') ?? 0;
        final forceUpdate = data['force_update'] as bool? ?? false;
        final storeUrl = data['play_store_url']?.toString() ?? 'https://play.google.com/store/apps/details?id=com.ELT_EMP.as_f';
        
        // This local version matches version 8 (the one currently live in store).
        // For your next push, change this to 9 so it matches build.gradle.kts!
        const int localAppVersionCode = 8; 
        
        if (latestVersion > localAppVersionCode && forceUpdate) {
          _showForcedUpdateDialog(storeUrl);
        }
      }
    } catch (e) {
      print('Update check bypassed: $e'); // Fails silently to prevent locking users out if endpoint isn't ready
    }
  }

  void _showForcedUpdateDialog(String storeUrl) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, // Disables back button on Android
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.system_update_rounded, color: Colors.teal.shade700, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Update Required',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: const Text(
              'A critical update is available for ELT_EMP. Please update to the latest version to continue using the application.',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            actions: [
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.shopping_bag_rounded), // Generic shopping/store bag icon
                    label: const Text(
                      'UPDATE NOW',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    onPressed: () async {
                      final url = Uri.parse(storeUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _initializeApp() async {
    unawaited(_checkAppUpdate());
    unawaited(_requestBatteryOptimization());
    final prefs = await SharedPreferences.getInstance();
    final storedEmpId = prefs.getString(_prefKeyEmpId);

    print('DEBUG ADMIN CHECK START:');
    print('  - widget.empId: "${widget.empId}"');
    print('  - storedEmpId in prefs: "$storedEmpId"');
    print('  - userRole in prefs: "${prefs.getString('userRole')}"');
    print('  - savedIsAdmin in prefs: "${prefs.getBool('isAdminUser')}"');

    if (widget.empId.isEmpty) {
      _handleError('Invalid employee ID', Exception('widget.empId is empty'));
      await _showInvalidEmpIdDialog();
      return;
    }

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastOpenedDate = prefs.getString('last_opened_date') ?? '';

    if (storedEmpId != widget.empId) {
      final savedLogo = prefs.getString('companyLogo') ?? '';
      final savedRole = prefs.getString('userRole') ?? '';
      final savedFcm  = prefs.getString('fcm_token') ?? '';
      final savedIsAdmin = prefs.getBool('isAdminUser') ?? false;
      await prefs.clear();
      await prefs.setString(_prefKeyEmpId, widget.empId);
      await prefs.setString('last_opened_date', todayStr);
      await prefs.setString('authToken', widget.authToken);
      await prefs.setString('deviceSerialNumber', widget.deviceSerialNumber);
      if (savedLogo.isNotEmpty) await prefs.setString('companyLogo', savedLogo);
      if (savedRole.isNotEmpty) await prefs.setString('userRole', savedRole);
      if (savedFcm.isNotEmpty)  await prefs.setString('fcm_token', savedFcm);
      if (savedIsAdmin) await prefs.setBool('isAdminUser', true);
      print('Cleared SharedPreferences for new empId: ${widget.empId}');
      isCheckedIn = false;
      isAllowedToCheckIn = true;
      isAllowedToCheckOut = false;
      isShiftSelectable = true;
      selectedShift = null;
      workingDuration = Duration.zero;
      checkInTime = '--:--:--';
      checkOutTime = '--:--:--';
      sessionStart = null;
    } else {
      if (lastOpenedDate != todayStr) {
        // It's a new day! Reset yesterday's stored times
        print('New day detected ($todayStr != $lastOpenedDate). Resetting daily check-in/out state.');
        await prefs.setString('last_opened_date', todayStr);
        await prefs.setBool(_prefKeyCheckedIn, false);
        await prefs.setString(_prefKeyWorkingDuration, '00:00:00');
        await prefs.setString(_prefKeyCheckInTime, '--:--:--');
        await prefs.setString(_prefKeyCheckOutTime, '--:--:--');
        await prefs.setString(_prefKeySessionStart, '');
        await prefs.setString(_prefKeySelectedShift, '');

        isCheckedIn = false;
        isAllowedToCheckIn = true;
        isAllowedToCheckOut = false;
        isShiftSelectable = true;
        selectedShift = null;
        workingDuration = Duration.zero;
        checkInTime = '--:--:--';
        checkOutTime = '--:--:--';
        sessionStart = null;
      } else {
        workingDuration = _parseDuration(
          prefs.getString(_prefKeyWorkingDuration) ?? '00:00:00',
        );
        checkInTime = prefs.getString(_prefKeyCheckInTime) ?? '--:--:--';
        checkOutTime = prefs.getString(_prefKeyCheckOutTime) ?? '--:--:--';
        final sessionStartStr = prefs.getString(_prefKeySessionStart);
        sessionStart =
            sessionStartStr != null ? DateTime.parse(sessionStartStr) : null;
        selectedShift = prefs.getString(_prefKeySelectedShift);
        if (selectedShift == '') selectedShift = null;
      }
      final retryFinalLocation = prefs.getBool('retry_final_location') ?? false;
      if (retryFinalLocation && isCheckedIn) {
        await _sendFinalLocationUpdate();
        await prefs.setBool('retry_final_location', false);
      }
    }

    final userRole = prefs.getString('userRole') ?? '';
    final savedIsAdmin = prefs.getBool('isAdminUser') ?? false;
    setState(() {
      isAdminUser = widget.isAdmin || userRole == 'admin' || widget.empId == '0' || widget.empId == 'admin' || savedIsAdmin;
    });
    print('DEBUG ADMIN CHECK END:');
    print('  - calculated isAdminUser: $isAdminUser');
    print('  - userRole: "$userRole"');
    print('  - savedIsAdmin: $savedIsAdmin');
    if (isAdminUser) {
      await prefs.setString('userRole', 'admin');
      await prefs.setBool('isAdminUser', true);
    }

    print(
      'Initial state - isCheckedIn: $isCheckedIn, isAllowedToCheckIn: $isAllowedToCheckIn, isAllowedToCheckOut: $isAllowedToCheckOut, selectedShift: $selectedShift',
    );

    await fetchShifts();
    await fetchStatus();
    await _startLocationMonitoring();
  }

  Future<void> _sendFinalLocationUpdate() async {
    try {
      final position = await _getCurrentLocation();
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'auth_token': widget.authToken,
        'emp_id': widget.empId,
        'shift_id': selectedShift,
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_serial_number': widget.deviceSerialNumber,
      };
      if (_isConnected) {
        await _sendLocationUpdateWithRetry(payload, prefs);
        print('Sent final location update on app termination');
      } else {
        await _storePendingLocation(payload, prefs);
        print('Stored final location for later sync');
      }
    } catch (e) {
      print('Failed to send final location update: $e');
      _handleError('Could not send final location update', e);
      final prefs = await SharedPreferences.getInstance();
      await _storePendingLocation({
        'auth_token': widget.authToken,
        'emp_id': widget.empId,
        'shift_id': selectedShift,
        'latitude': '0.0',
        'longitude': '0.0',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_serial_number': widget.deviceSerialNumber,
      }, prefs);
      await prefs.setBool('retry_final_location', true);
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyCheckedIn, isCheckedIn);
    await prefs.setString(
      _prefKeyWorkingDuration,
      _formatDuration(workingDuration),
    );
    await prefs.setString(_prefKeyCheckInTime, checkInTime);
    await prefs.setString(_prefKeyCheckOutTime, checkOutTime);
    await prefs.setString(
      _prefKeySessionStart,
      sessionStart?.toIso8601String() ?? '',
    );
    await prefs.setString(_prefKeySelectedShift, selectedShift ?? '');
    print(
      'Saved state - isCheckedIn: $isCheckedIn, workingDuration: ${_formatDuration(workingDuration)}, selectedShift: $selectedShift',
    );
  }

  Future<void> _syncPendingLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingLocations =
        prefs.getStringList(_prefKeyPendingLocations) ?? [];
    if (pendingLocations.isEmpty || !_isConnected) return;

    for (var locationJson in pendingLocations) {
      try {
        final payload = jsonDecode(locationJson);
        await _sendLocationUpdateWithRetry(payload, prefs);
      } catch (e) {
        print('Failed to sync pending location: $e');
        continue;
      }
    }
    await prefs.setStringList(_prefKeyPendingLocations, []);
    print('Cleared pending locations after sync');
  }

  Future<Map<String, dynamic>> _sendLocationUpdateWithRetry(
    Map<String, dynamic> payload,
    SharedPreferences prefs,
  ) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await ApiService.sendLocationUpdate(payload);
        final data = jsonDecode(response.body);
        print('Location Update Response: $data');

        if (data['status'] == 'ok' && data['auto_checkout'] == true) {
          setState(() {
            isCheckedIn = false;
            isAllowedToCheckIn = true;
            isAllowedToCheckOut = false;
            isShiftSelectable = true;
            selectedShift = null;
            checkOutTime = DateFormat('hh:mm:ss a').format(DateTime.now());
            workingDuration = _parseDuration(
              data['cumulative_working_hours'] ?? '00:00:00',
            );
            totalWorkingHours = _formatDuration(workingDuration);
          });
          stopWorkingTimer();
          _stopLocationSending();
          await _saveState();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Auto-Checkout triggered by server'),
              ),
            );
          }
          // Show notification for auto-checkout even in UI thread
          await _showNotification(
            title: 'Auto Checkout',
            body:
                'Server triggered auto-checkout. Total: ${data['cumulative_working_hours']}',
          );
        }
        return data; // Return data for background handling
      } catch (e) {
        print('Attempt $attempt failed: $e');
        if (attempt == 3) {
          await _storePendingLocation(payload, prefs);
          print('Max retries reached, stored location for later sync');
        }
        await Future.delayed(Duration(milliseconds: 1000 * attempt));
      }
    }
    return {}; // Empty on failure
  }

  Future<void> _startLocationMonitoring() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _handleError(
        'Location services disabled',
        Exception('Location services are disabled'),
      );
      return;
    }

    // 1. Request foreground location first
    if (!await Permission.location.isGranted) {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        _handleError(
          'Location permission denied',
          Exception('Foreground location permission required'),
        );
        return;
      }
    }

    // 2. Request background location next
    if (!await Permission.locationAlways.isGranted) {
      final status = await Permission.locationAlways.request();
      if (!status.isGranted) {
        print('Background location permission denied - continuing in foreground mode silently');
      }
    }

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,                    // ← important
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: 'attendance_foreground', // new channel
        // ───────────── Persistent notification ─────────────
        initialNotificationTitle: 'Attendance Active',
        initialNotificationContent: 'Location is being tracked for check-in / check-out',
        // Show this notification permanently while checked-in
        foregroundServiceNotificationId: 1001,
        foregroundServiceTypes: [
          AndroidForegroundType.location,
          AndroidForegroundType.dataSync,
          AndroidForegroundType.connectedDevice,   // extra protection
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    await service.startService();

    if (isCheckedIn) {
      await _scheduleFinalLocationUpdate();
    }

    positionStream?.cancel();
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen(
      (position) async {
        if (isCheckedIn) {
          _startLocationSending();
        } else {
          _stopLocationSending();
          await Workmanager().cancelByUniqueName(finalLocationTask);
        }

        FlutterBackgroundService().invoke('updateState', {
          'isCheckedIn': isCheckedIn,
          'empId': widget.empId,
          'authToken': widget.authToken,
          'deviceSerialNumber': widget.deviceSerialNumber,
          'selectedShift': selectedShift,
        });
      },
      onError: (error) {
        _handleError('Location stream error', error);
        if (isCheckedIn) {
          _scheduleFinalLocationUpdate();
        }
      },
    );
  }

  Future<void> _sendLocationUpdate({
    required String empId,
    required String authToken,
    required String deviceSerialNumber,
    required String? shiftId,
    required Position position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'auth_token': authToken,
      'emp_id': empId,
      'shift_id': shiftId,
      'latitude': position.latitude.toString(),
      'longitude': position.longitude.toString(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_serial_number': deviceSerialNumber,
    };
    if (_isConnected) {
      await _sendLocationUpdateWithRetry(payload, prefs);
    } else {
      await _storePendingLocation(payload, prefs);
    }
  }

  void _startLocationSending() {
    _stopLocationSending();
    if (isCheckedIn) {
      locationSendTimer = Timer.periodic(const Duration(seconds: 600), (
        _,
      ) async {
        try {
          final position = await _getCurrentLocation();
          await _sendLocationUpdate(
            empId: widget.empId,
            authToken: widget.authToken,
            deviceSerialNumber: widget.deviceSerialNumber,
            shiftId: selectedShift,
            position: position,
          );
        } catch (e) {
          _handleError('Failed to send location update', e);
        }
      });
      _getCurrentLocation().then((position) {
        _sendLocationUpdate(
          empId: widget.empId,
          authToken: widget.authToken,
          deviceSerialNumber: widget.deviceSerialNumber,
          shiftId: selectedShift,
          position: position,
        );
      });
    }
  }

  void _stopLocationSending() {
    locationSendTimer?.cancel();
    locationSendTimer = null;
  }

  @pragma('vm:entry-point')
  void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    print('Background service started');

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        print('Setting as foreground service');
        service.setAsForegroundService();
      });

      // ← Change 'stopService' to 'stop' to match what we invoke
      service.on('stop').listen((event) async {
        print('Received stop command from main app - shutting down service');
        final prefs = await SharedPreferences.getInstance();
        final isCheckedIn = prefs.getBool(_prefKeyCheckedIn) ?? false;
        if (isCheckedIn) {
          print('User is still checked-in → background tracking will rely on Workmanager');
        }
        service.stopSelf();  // This actually stops the service
      });
    }

    // Load initial state from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    bool isCheckedIn = prefs.getBool(_prefKeyCheckedIn) ?? false;
    String? empId = prefs.getString(_prefKeyEmpId);
    String? authToken = prefs.getString('authToken');
    String? deviceSerialNumber = prefs.getString('deviceSerialNumber');
    String? selectedShift = prefs.getString(_prefKeySelectedShift);

    // Listen for state updates from main app
    service.on('updateState').listen((event) async {
      if (event != null) {
        isCheckedIn = event['isCheckedIn'] ?? isCheckedIn;
        empId = event['empId'] ?? empId;
        authToken = event['authToken'] ?? authToken;
        deviceSerialNumber = event['deviceSerialNumber'] ?? deviceSerialNumber;
        selectedShift = event['selectedShift'] ?? selectedShift;

        print('Background: State updated → isCheckedIn: $isCheckedIn');

        await prefs.setBool(_prefKeyCheckedIn, isCheckedIn);
        await prefs.setString(_prefKeySelectedShift, selectedShift ?? '');
      }
    });

    // Initialize notifications in background isolate
    final bgPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidInit =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    await bgPlugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'attendance_channel_id',
      'Attendance Notifications',
      description: 'Notifications for attendance events',
      importance: Importance.max,
      playSound: true,
    );
    await bgPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Periodic location update timer (every 10 minutes)
    Timer.periodic(const Duration(seconds: 600), (timer) async {
      // Stop timer if user is no longer checked in
      if (!isCheckedIn) {
        print('User not checked in → stopping location timer');
        timer.cancel();
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final payload = {
          'auth_token': authToken ?? '',
          'emp_id': empId ?? '',
          'shift_id': selectedShift ?? '',
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'device_serial_number': deviceSerialNumber ?? '',
        };

        final response = await ApiService.sendLocationUpdate(payload);

        final data = jsonDecode(response.body);

        // Handle auto-checkout from server
        if (data['auto_checkout'] == true) {
          print('Auto-checkout triggered in background');
          await bgPlugin.show(
            0,
            'Auto Checkout',
            'Triggered in background. Total: ${data['cumulative_working_hours'] ?? 'N/A'}',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'attendance_channel_id',
                'Attendance Notifications',
                importance: Importance.max,
              ),
            ),
          );

          // Update local state
          await prefs.setBool(_prefKeyCheckedIn, false);
          await prefs.setString(_prefKeySelectedShift, '');
        }
      } catch (e) {
        print('Background location update failed silently: $e');
      }
    });

    print('Background service fully initialized and running');
  }
  @pragma('vm:entry-point')
  Future<bool> onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final isCheckedIn = prefs.getBool(_prefKeyCheckedIn) ?? false;
    if (!isCheckedIn) {
      await Workmanager().cancelByUniqueName(finalLocationTask);
      print(
        'Canceled Workmanager task in iOS background as user is not checked in',
      );
      return true;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final storedAuthToken = prefs.getString('authToken') ?? '';
      final storedEmpId = prefs.getString(_prefKeyEmpId) ?? '';
      final storedDeviceSerial = prefs.getString('deviceSerialNumber') ?? '';

      final payload = {
        'auth_token': storedAuthToken,
        'emp_id': storedEmpId,
        'shift_id': prefs.getString(_prefKeySelectedShift),
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_serial_number': storedDeviceSerial,
      };
      if (_isConnected) {
        await _sendLocationUpdateWithRetry(payload, prefs);
      } else {
        await _storePendingLocation(payload, prefs);
      }
      await Workmanager().registerPeriodicTask(
        finalLocationTask,
        finalLocationTask,
        frequency: const Duration(minutes: 1),
        inputData: {
          'authToken': storedAuthToken,
          'empId': storedEmpId,
          'shiftId': prefs.getString(_prefKeySelectedShift),
          'deviceSerialNumber': storedDeviceSerial,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      print('Scheduled Work manager periodic task for iOS background');
    } catch (e) {
      _handleError('iOS background location update failed', e);
      await _storePendingLocation({
        'auth_token': widget.authToken,
        'emp_id': widget.empId,
        'shift_id': prefs.getString(_prefKeySelectedShift),
        'latitude': '0.0',
        'longitude': '0.0',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_serial_number': widget.deviceSerialNumber,
      }, prefs);
    }
    return true;
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled.');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied.');
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  void _handleError(String message, dynamic error, [StackTrace? stackTrace]) {
    print('$message: $error${stackTrace != null ? '\n$stackTrace' : ''}');
    if (mounted) {
      if (isAdminUser) {
        return; // Don't show error SnackBars or notifications for admins
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$message: ${error.toString().split(':').last.trim()}'),
        ),
      );
      _showNotification(title: 'Error', body: message); // Notify on error
    }
  }

  Future<void> _showNoInternetDialog() async {
    if (!mounted || _isNoInternetDialogShowing) return;
    _isNoInternetDialogShowing = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('No Internet Connection'),
            content: const Text(
              'Please check your internet connection and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  _isNoInternetDialogShowing = false;
                  if (await _checkInternetConnectivity()) {
                    setState(() => _isConnected = true);
                    await fetchShifts();
                    await fetchStatus();
                    await _syncPendingLocations();
                  } else {
                    _showNoInternetDialog();
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
    );
    await _showNotification(
      title: 'No Internet',
      body: 'Check-in/out requires connection',
    );
  }

  void _populateDefaultShifts() {
    final nowForDefaults = DateTime.now();
    final defaultsDateStr = '${nowForDefaults.year}-${nowForDefaults.month.toString().padLeft(2, '0')}-${nowForDefaults.day.toString().padLeft(2, '0')}';
    
    final List<Map<String, dynamic>> defaultShifts = [
      {
        'id': '1',
        'name': 'General Shift : 09:00 AM - 05:00 PM',
        'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 9, 0),
        'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 17, 0),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '2',
        'name': 'A Shift : 06:00 AM - 02:00 PM',
        'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 6, 0),
        'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 14, 0),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '3',
        'name': 'B Shift : 02:00 PM - 10:00 PM',
        'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 14, 0),
        'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 22, 0),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '4',
        'name': 'C Shift : 10:00 PM - 06:00 AM',
        'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 22, 0),
        'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 6, 0).add(const Duration(days: 1)),
        'isActive': true,
        'date': defaultsDateStr,
      }
    ];

    setState(() {
      empShifts = defaultShifts;
      isShiftSelectable = true;
    });

    if (!isCheckedIn) {
      _autoSelectShift();
    }
  }

  Future<void> fetchShifts() async {
    if (!_isConnected) {
      _handleError('No internet connection', Exception('Please try again'));
      if (!_isNoInternetDialogShowing) {
        _showNoInternetDialog();
      }
      return;
    }
    tz_data.initializeTimeZones();
    final ist = tz.getLocation('Asia/Kolkata');
    setState(() => isShiftsLoading = true);
    try {
      final response = await ApiService.fetchShifts(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      print('Shifts API Response: $data');
      if (response.statusCode == 200 && data['status'] == 'success') {
        final List shiftsData = data['shifts'] ?? [];
        final now = tz.TZDateTime.now(ist);
        final today = DateTime(now.year, now.month, now.day);
        print('Current Time (IST): $now, Today: $today');
        final List<Map<String, dynamic>> newShifts = [];
        for (var shift in shiftsData) {
          final shiftTimeRaw = shift['shift_time']?.toString() ?? '-';
          var shiftName = shift['shift_name']?.toString() ?? '';
          if (shiftName.trim().toLowerCase() == 'open shift') {
            shiftName = 'General Shift';
          }
          String shiftDateStr;
          String shiftTime;
          if (shiftTimeRaw.contains('(') && shiftTimeRaw.contains(')')) {
            final parts = shiftTimeRaw.split('(');
            shiftTime = parts[0].trim();
            shiftDateStr = parts[1].replaceAll(')', '').trim();
          } else {
            shiftTime = shiftTimeRaw;
            shiftDateStr =
                shift['date']?.toString() ??
                '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          }
          DateTime? startTime;
          DateTime? endTime;
          String displayTime = shiftTime;
          try {
            final shiftDate = DateTime.parse(shiftDateStr);
            if (shiftTime == '-' || shiftTime.isEmpty) {
              displayTime = '09:00 AM - 05:00 PM';
            } else if (RegExp(
              r'^\d{2}:\d{2}-\d{2}:\d{2}$',
            ).hasMatch(shiftTime)) {
              final parts = shiftTime.split('-');
              final startParts = parts[0].trim().split(':');
              final endParts = parts[1].trim().split(':');
              startTime = DateTime(
                shiftDate.year,
                shiftDate.month,
                shiftDate.day,
                int.parse(startParts[0]),
                int.parse(startParts[1]),
              );
              endTime = DateTime(
                shiftDate.year,
                shiftDate.month,
                shiftDate.day,
                int.parse(endParts[0]),
                int.parse(endParts[1]),
              );
              if (!endTime.isAfter(startTime)) {
                endTime = endTime.add(const Duration(days: 1));
              }
              final startHour = int.parse(startParts[0]);
              final startMin = int.parse(startParts[1]);
              final endHour = int.parse(endParts[0]);
              final endMin = int.parse(endParts[1]);
              final startPeriod = startHour >= 12 ? 'PM' : 'AM';
              final endPeriod = endHour >= 12 ? 'PM' : 'AM';
              final start12 =
                  startHour > 12
                      ? startHour - 12
                      : (startHour == 0 ? 12 : startHour);
              final end12 =
                  endHour > 12
                      ? endHour - 12
                      : (endHour == 0 ? 12 : endHour);
              final overnight = endTime.day != startTime.day;
              displayTime =
                  '$start12:${startMin.toString().padLeft(2, '0')} $startPeriod - '
                  '$end12:${endMin.toString().padLeft(2, '0')} $endPeriod${overnight ? ' (Next Day)' : ''}';
            } else {
              print(
                'Invalid shift time format for ${shift['shift_name']}: $shiftTime (raw: $shiftTimeRaw)',
              );
            }
          } catch (e) {
            _handleError('Failed parsing shift ${shift['shift_name']}', e);
          }
          newShifts.add({
            'id': shift['id']?.toString() ?? '',
            'name': '$shiftName : $displayTime',
            'startTime': startTime,
            'endTime': endTime,
            'isActive': true,
            'date': shiftDateStr,
          });
        }

        // Always ensure all four standard shifts are present in the list
        final nowForDefaults = DateTime.now();
        final defaultsDateStr = '${nowForDefaults.year}-${nowForDefaults.month.toString().padLeft(2, '0')}-${nowForDefaults.day.toString().padLeft(2, '0')}';
        
        bool hasGeneral = newShifts.any((s) => s['name'].toString().toLowerCase().contains('general'));
        bool hasA = newShifts.any((s) => s['name'].toString().toLowerCase().contains('a shift') || s['name'].toString().toLowerCase().contains('shift a'));
        bool hasB = newShifts.any((s) => s['name'].toString().toLowerCase().contains('b shift') || s['name'].toString().toLowerCase().contains('shift b'));
        bool hasC = newShifts.any((s) => s['name'].toString().toLowerCase().contains('c shift') || s['name'].toString().toLowerCase().contains('shift c'));

        if (!hasGeneral) {
          newShifts.add({
            'id': '1',
            'name': 'General Shift : 09:00 AM - 05:00 PM',
            'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 9, 0),
            'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 17, 0),
            'isActive': true,
            'date': defaultsDateStr,
          });
        }
        if (!hasA) {
          newShifts.add({
            'id': '2',
            'name': 'A Shift : 06:00 AM - 02:00 PM',
            'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 6, 0),
            'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 14, 0),
            'isActive': true,
            'date': defaultsDateStr,
          });
        }
        if (!hasB) {
          newShifts.add({
            'id': '3',
            'name': 'B Shift : 02:00 PM - 10:00 PM',
            'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 14, 0),
            'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 22, 0),
            'isActive': true,
            'date': defaultsDateStr,
          });
        }
        if (!hasC) {
          newShifts.add({
            'id': '4',
            'name': 'C Shift : 10:00 PM - 06:00 AM',
            'startTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 22, 0),
            'endTime': DateTime(nowForDefaults.year, nowForDefaults.month, nowForDefaults.day, 6, 0).add(const Duration(days: 1)),
            'isActive': true,
            'date': defaultsDateStr,
          });
        }

        setState(() {
          empShifts = newShifts;
          isShiftSelectable = true;
        });

        if (!isCheckedIn) {
          _autoSelectShift();
        }
      } else if (data['message']?.toLowerCase().contains('invalid token') ??
          false) {
        await _showInvalidTokenDialog();
      } else {
        _populateDefaultShifts();
        _handleError(
          'Failed to fetch shifts',
          Exception(data['message'] ?? 'Unknown error'),
        );
      }
    } catch (e) {
      _populateDefaultShifts();
      _handleError('Error fetching shifts', e);
    } finally {
      setState(() => isShiftsLoading = false);
    }
  }

  Future<void> fetchStatus() async {
    if (!_isConnected) {
      _handleError('No internet connection', Exception('Please try again'));
      if (!_isNoInternetDialogShowing) {
        _showNoInternetDialog();
      }
      return;
    }
    if (widget.empId.isEmpty) {
      _handleError(
        'Invalid employee ID',
        Exception('empId is empty in fetchStatus'),
      );
      await _showInvalidEmpIdDialog();
      return;
    }
    try {
      setState(() => isStatusLoading = true);
      final response = await ApiService.fetchStatus(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      print('Status API Response: $data');
      if (response.statusCode == 200 && data['status'] == 'success') {
        String displayTime = 'General Shift';
        DateTime? startTime;
        DateTime? endTime;
        final shiftTime = data['shift_time']?.toString() ?? '-';
        final shiftId = data['shift_id']?.toString() ?? '';
        final shiftNameRaw = data['shift_name']?.toString() ?? '';
        final shiftName = shiftNameRaw.trim().toLowerCase() == 'open shift'
            ? 'General Shift'
            : shiftNameRaw;
        final now = tz.TZDateTime.now(tz.getLocation('Asia/Kolkata'));
        final today = DateTime(now.year, now.month, now.day);
        String shiftDateStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        if (shiftTime != '-' &&
            shiftTime.isNotEmpty &&
            RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$').hasMatch(shiftTime)) {
          final parts = shiftTime.split('-');
          final startParts = parts[0].trim().split(':');
          final endParts = parts[1].trim().split(':');
          startTime = DateTime(
            today.year,
            today.month,
            today.day,
            int.parse(startParts[0]),
            int.parse(startParts[1]),
          );
          endTime = DateTime(
            today.year,
            today.month,
            today.day,
            int.parse(endParts[0]),
            int.parse(endParts[1]),
          );
          if (!endTime.isAfter(startTime)) {
            endTime = endTime.add(const Duration(days: 1));
          }
          final startHour = int.parse(startParts[0]);
          final startMin = int.parse(startParts[1]);
          final endHour = int.parse(endParts[0]);
          final endMin = int.parse(endParts[1]);
          final startPeriod = startHour >= 12 ? 'PM' : 'AM';
          final endPeriod = endHour >= 12 ? 'PM' : 'AM';
          final start12 =
              startHour > 12
                  ? startHour - 12
                  : (startHour == 0 ? 12 : startHour);
          final end12 =
              endHour > 12 ? endHour - 12 : (endHour == 0 ? 12 : endHour);
          final overnight = endTime.day != startTime.day;
          displayTime =
              '$start12:${startMin.toString().padLeft(2, '0')} $startPeriod - '
              '$end12:${endMin.toString().padLeft(2, '0')} $endPeriod${overnight ? ' (Next Day)' : ''}';
        }
        setState(() {
          isCheckedIn = data['current_status'] == 'checked_in';
          isAllowedToCheckIn = !isCheckedIn;
          isAllowedToCheckOut = isCheckedIn;
          isShiftSelectable = true;
          selectedShift = isCheckedIn ? shiftId : null;
          workingDuration = _parseDuration(
            data['cumulative_working_hours'] ?? '00:00:00',
          );
          final lastCheckInTimeStr = data['last_check_in_time'];
          if (isCheckedIn &&
              lastCheckInTimeStr != null &&
              lastCheckInTimeStr != 'NA') {
            sessionStart = DateTime.parse(lastCheckInTimeStr).toLocal();
            final elapsed = DateTime.now().difference(sessionStart!);
            workingDuration += elapsed;
            startWorkingTimer();
            _startLocationSending();
          } else {
            sessionStart = null;
            stopWorkingTimer();
            _stopLocationSending();
          }
          checkInTime =
              lastCheckInTimeStr != null && lastCheckInTimeStr != 'NA'
                  ? _formatToTime(lastCheckInTimeStr)
                  : '--:--:--';
          checkOutTime =
              data['last_check_out_time'] != null &&
                      data['last_check_out_time'] != 'NA'
                  ? _formatToTime(data['last_check_out_time'])
                  : '--:--:--';
          totalWorkingHours = _formatDuration(workingDuration);
          if (isCheckedIn && shiftId.isNotEmpty) {
            if (!empShifts.any((shift) => shift['id'] == shiftId)) {
              empShifts.add({
                'id': shiftId,
                'name': '$shiftName : $displayTime',
                'startTime': startTime,
                'endTime': endTime,
                'isActive': true,
                'date': shiftDateStr,
              });
            }
          }
        });
        if (!isCheckedIn) {
          _autoSelectShift();
        }
        await _saveState();
        FlutterBackgroundService().invoke('updateState', {
          'isCheckedIn': isCheckedIn,
          'empId': widget.empId,
          'authToken': widget.authToken,
          'deviceSerialNumber': widget.deviceSerialNumber,
          'selectedShift': selectedShift,
        });
        print(
          'Updated state - isCheckedIn: $isCheckedIn, isAllowedToCheckIn: $isAllowedToCheckIn, isAllowedToCheckOut: $isAllowedToCheckOut, selectedShift: $selectedShift, empShifts: ${empShifts.length}',
        );
      } else {
        _handleError(
          'Failed to fetch status',
          Exception(data['message'] ?? 'Unknown error'),
        );
        if (data['message']?.toLowerCase().contains('invalid token') ?? false) {
          await _showInvalidTokenDialog();
        }
      }
    } catch (e) {
      _handleError('Error fetching status', e);
    } finally {
      setState(() => isStatusLoading = false);
    }
  }

  Future<void> handleCheckIn() async {
    if (!_isConnected) {
      if (!_isNoInternetDialogShowing) {
        _showNoInternetDialog();
        await _showNotification(
          title: 'No Internet',
          body: 'Check-in needs internet. Actions will sync later.',
        );
      }
      return;
    }

    if (selectedShift == null || isProcessingCheckIn) {
      _handleError('Invalid shift', Exception('Select shift first'));
      await _showNotification(
        title: 'Invalid Shift',
        body: 'Please select a valid shift before checking in.',
      );
      return;
    }

    bool confirmed = await _showConfirmationDialog(
      context,
      'Are you sure you want to check in?',
    );
    if (!confirmed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in cancelled.'), duration: Duration(seconds: 2)),
        );
      }
      await _showNotification(title: 'Cancelled', body: 'Check-in cancelled by you.');
      return;
    }

    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Location Required'),
            content: const Text('Please enable location services to check in.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openLocationSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      await _showNotification(title: 'Location Off', body: 'Enable location to check in.');
      return;
    }

    try {
      setState(() {
        isProcessingCheckIn = true;
        isProcessing = true;
      });

      final now = DateTime.now().toUtc().toIso8601String();
      final position = await _getCurrentLocation();

      final response = await ApiService.checkIn(
        authToken: widget.authToken,
        empId: widget.empId,
        shiftId: selectedShift!,
        latitude: position.latitude.toString(),
        longitude: position.longitude.toString(),
        timestamp: now,
        deviceSerialNumber: widget.deviceSerialNumber,
      );

      final data = jsonDecode(response.body);
      print('CheckIn Response: $data');

      if (response.statusCode == 200 && data['status'] == 'success') {
        // Update UI & state
        await fetchStatus();
        final cumTimeStr = data['cumulative_working_hours'] ?? '00:00:00';
        workingDuration = _parseDuration(cumTimeStr);
        sessionStart = DateTime.now();
        checkInTime = DateFormat('hh:mm:ss a').format(sessionStart!);
        setState(() => totalWorkingHours = _formatDuration(workingDuration));

        await _saveState();

        // Start timers & location sending
        if (isCheckedIn) {
          startWorkingTimer();
          _startLocationSending();
        }

        // Update background service state
        FlutterBackgroundService().invoke('updateState', {
          'isCheckedIn': isCheckedIn,
          'empId': widget.empId,
          'authToken': widget.authToken,
          'deviceSerialNumber': widget.deviceSerialNumber,
          'selectedShift': selectedShift,
        });

        // Show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Checked in successfully'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await _showNotification(
          title: 'Check-In Success',
          body: '${data['message'] ?? 'Checked in at $checkInTime'} - Shift: $selectedShift',
        );

        // VERY IMPORTANT: Ask user to disable battery optimization
        if (!await Permission.ignoreBatteryOptimizations.isGranted) {
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text("Important for Accurate Attendance"),
                content: const Text(
                  "To make sure your attendance is recorded even when the app is closed:\n\n"
                      "→ Go to Settings → Apps → This App → Battery → Choose 'Unrestricted' or 'No restrictions'\n\n"
                      "Without this, Android may stop tracking when app is closed.",
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await Permission.ignoreBatteryOptimizations.request();
                      Navigator.pop(ctx);
                    },
                    child: const Text("Open Settings Now"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Later"),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Check-In Failed'), duration: const Duration(seconds: 3)),
          );
        }
        _handleError('Check-In Failed', Exception(data['message'] ?? 'Unknown error'));
        await _showNotification(title: 'Check-In Failed', body: data['message'] ?? 'Try again later.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-In Error: $e'), duration: const Duration(seconds: 3)),
        );
      }
      _handleError('Check-In Error', e);
      await _showNotification(title: 'Check-In Error', body: 'Error: $e');
    } finally {
      setState(() {
        isProcessingCheckIn = false;
        isProcessing = false;
      });
    }
  }

  Future<void> handleCheckOut() async {
    if (!_isConnected) {
      if (!_isNoInternetDialogShowing) {
        _showNoInternetDialog();
        await _showNotification(
          title: 'No Internet',
          body: 'Check-out needs internet. Actions will sync later.',
        );
      }
      return;
    }

    if (isProcessingCheckOut) {
      _handleError('Checkout in progress', Exception('Already processing'));
      await _showNotification(title: 'In Progress', body: 'Checkout already running. Wait.');
      return;
    }

    if (selectedShift == null) {
      _handleError('No shift', Exception('No shift selected'));
      await _showNotification(title: 'No Shift', body: 'Select shift before checkout.');
      return;
    }

    bool confirmed = await _showConfirmationDialog(
      context,
      'Are you sure you want to check out?',
    );
    if (!confirmed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-out cancelled.'), duration: Duration(seconds: 2)),
        );
      }
      await _showNotification(title: 'Cancelled', body: 'Check-out cancelled by you.');
      return;
    }

    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Location Required'),
            content: const Text('Please enable location services to check out.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openLocationSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      await _showNotification(title: 'Location Off', body: 'Enable location to check out.');
      return;
    }

    setState(() {
      isProcessingCheckOut = true;
      isProcessing = true;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final position = await _getCurrentLocation();

      final response = await ApiService.checkOut(
        authToken: widget.authToken,
        empId: widget.empId,
        shiftId: selectedShift!,
        latitude: position.latitude.toString(),
        longitude: position.longitude.toString(),
        timestamp: now,
        deviceSerialNumber: widget.deviceSerialNumber,
      );

      final data = jsonDecode(response.body);
      print('CheckOut Response: $data');

      if (response.statusCode == 200 && data['status'] == 'success') {
        await fetchStatus();
        stopWorkingTimer();
        _stopLocationSending();

        final nowLocal = DateTime.now();
        checkOutTime = DateFormat('hh:mm:ss a').format(nowLocal);
        final cumTimeStr = data['cumulative_working_hours'] ?? '00:00:00';
        workingDuration = _parseDuration(cumTimeStr);

        setState(() => totalWorkingHours = _formatDuration(workingDuration));

        await _saveState();

        // Stop Workmanager
        await Workmanager().cancelByUniqueName(finalLocationTask);
        print('Workmanager task cancelled on check-out');

        // ──────────────────────────────────────────────────────────────
        // STOP FOREGROUND SERVICE CORRECTLY (no await needed)
        // ──────────────────────────────────────────────────────────────
        final service = FlutterBackgroundService();
        service.invoke('stop');  // ← No await here
        print('Foreground service stop requested');

        // Update background state
        FlutterBackgroundService().invoke('updateState', {
          'isCheckedIn': isCheckedIn,
          'empId': widget.empId,
          'authToken': widget.authToken,
          'deviceSerialNumber': widget.deviceSerialNumber,
          'selectedShift': selectedShift,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Checked out successfully'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await _showNotification(
          title: 'Check-Out Success',
          body: '${data['message'] ?? 'Checked out at $checkOutTime'}. Total: $totalWorkingHours',
        );

        // Do not clear SharedPreferences or navigate to Login Screen on successful checkout,
        // so that the user remains logged in.
      } else if (data['message']?.toLowerCase().contains('invalid token') ?? false) {
        await _showInvalidTokenDialog();
        await _showNotification(title: 'Session Expired', body: 'Please log in again.');
      } else {
        await fetchStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Check-Out Failed'), duration: const Duration(seconds: 3)),
          );
        }
        _handleError('Check-Out Failed', Exception(data['message'] ?? 'Unknown'));
        await _showNotification(title: 'Check-Out Failed', body: data['message'] ?? 'Try again.');
      }
    } catch (e) {
      await fetchStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-Out Error: $e'), duration: const Duration(seconds: 3)),
        );
      }
      _handleError('Check-Out Error', e);
      await _showNotification(title: 'Check-Out Error', body: 'Error: $e');
    } finally {
      setState(() {
        isProcessingCheckOut = false;
        isProcessing = false;
      });
    }
  }

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'attendance_channel_id',
          'Attendance Notifications',
          channelDescription:
              'Notifications for check-in/out events and errors',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'Attendance Alert',
          icon: '@mipmap/ic_launcher',
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(sound: 'default'),
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().hashCode,
      title,
      body,
      details,
    );
  }

  Future<bool> _showConfirmationDialog(
    BuildContext context,
    String message,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirmation'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Yes'),
                ),
              ],
            );
          },
        ) ??
        false;
  }



  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _showInvalidTokenDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Session Expired',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Your session has expired or your account was signed in from another device. Please log in again.',
              style: TextStyle(fontSize: 18),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  debugPrint('Cleared SharedPreferences for session reset');
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _showInvalidEmpIdDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Invalid Employee ID',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Invalid employee ID detected. Please log in again using the logout option to continue.',
              style: TextStyle(fontSize: 18),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  void startWorkingTimer() {
    workingTimer?.cancel();
    workingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        workingDuration += const Duration(seconds: 1);
        totalWorkingHours = _formatDuration(workingDuration);
      });
    });
  }

  void stopWorkingTimer() {
    workingTimer?.cancel();
    workingTimer = null;
  }

  void updateTime() {
    final now = DateTime.now();
    setState(() {
      currentTime = DateFormat('hh:mm:ss a').format(now);
    });

    // Check for 9:15 AM Check-In Reminder
    if (now.hour == 9 && now.minute == 15 && !isCheckedIn) {
      final today = DateTime(now.year, now.month, now.day);
      if (_lastReminderDate == null || _lastReminderDate != today) {
        _lastReminderDate = today;
        _showCheckInReminder();
      }
    }
  }

  Future<void> _showCheckInReminder() async {
    // 1. Show local push notification
    await _showNotification(
      title: 'Shift Reminder',
      body: "It's 9:15 AM! Don't forget to check in for your shift.",
    );

    // 2. Show in-app popup dialog if mounted
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Check-In Reminder',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "It's 9:15 AM! Don't forget to check in to record your attendance.",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
  }

  Duration _parseDuration(String timeStr) {
    try {
      final parts = timeStr.split(':').map(int.parse).toList();
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    } catch (_) {
      return Duration.zero;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatToTime(String isoTime) {
    try {
      final parsed = DateTime.parse(isoTime).toLocal();
      return DateFormat('hh:mm:ss a').format(parsed);
    } catch (_) {
      return '--:--:--';
    }
  }

  String _getGreetingMessage() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    final today = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.black54,
        showUnselectedLabels: true,
        currentIndex: _selectedIndex,
        onTap: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/attndance_logo.png'),
              size: 24,
              color: _selectedIndex == 0 ? Colors.greenAccent : Colors.black54,
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/leave_logo.png'),
              size: 24,
              color: _selectedIndex == 1 ? Colors.greenAccent : Colors.black54,
            ),
            label: 'Leaves',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/payslip_icon.png'),
              size: 24,
              color: _selectedIndex == 2 ? Colors.greenAccent : Colors.black54,
            ),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/approval_logos.png'),
              size: 24,
              color: _selectedIndex == 3 ? Colors.greenAccent : Colors.black54,
            ),
            label: 'Expenses',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/up_more.png'),
              size: 24,
              color: _selectedIndex == 4 ? Colors.greenAccent : Colors.black54,
            ),
            label: 'More',
          ),
        ],
      ),
      body: _getBodyWidget(_selectedIndex, today),
    );
  }

  Widget _getBodyWidget(int index, String today) {
    Widget mainContent() {
      if (index == 0) {
        print(
          'Button State: isAllowedToCheckIn=$isAllowedToCheckIn, isAllowedToCheckOut=$isAllowedToCheckOut, selectedShift=$selectedShift, isProcessing=$isProcessing, activeShift=${empShifts.any((shift) => shift['id'] == selectedShift && shift['isActive'] as bool)}',
        );
        return RefreshIndicator(
          onRefresh: () async {
            await fetchShifts();
            await fetchStatus();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isAdminUser)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IconButton(
                            icon: const Icon(
                              Icons.dashboard_rounded,
                              size: 30,
                              color: Colors.teal,
                            ),
                            tooltip: 'Admin Dashboard',
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminPage(
                                    empName: widget.empName,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    Center(
                      child: _companyLogoUrl.isNotEmpty
                          ? Image.network(
                              _companyLogoUrl,
                              height: 80,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  Image.asset('assets/eltrive_plan.png', height: 80),
                            )
                          : Image.asset('assets/eltrive_plan.png', height: 80),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(
                            Icons.menu,
                            size: 30,
                            color: Colors.black87,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmpProfile(
                                  empId: widget.empId,
                                  empName: widget.empName,
                                  authToken: widget.authToken,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${_getGreetingMessage()} : ',
                      style: const TextStyle(
                        color: Color(0xFF039C0D),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: widget.empName.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0C0D0C),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              currentTime,
              style: const TextStyle(
                fontSize: 34,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              today,
              style: const TextStyle(fontSize: 18, color: Colors.black54),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: isShiftsLoading || isStatusLoading
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: selectedShift,
                      isExpanded: true,
                      hint: const Text(
                        'Please Select Shift',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      dropdownColor: Colors.white,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        labelText: 'Shift Name',
                        labelStyle: TextStyle(
                          color: Colors.teal.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(Icons.badge_rounded, color: Colors.teal.shade700, size: 22),
                        filled: true,
                        fillColor: Colors.teal.shade50.withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.teal.shade100,
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.teal.shade700,
                            width: 1.5,
                          ),
                        ),
                      ),
                      icon: Icon(Icons.arrow_drop_down_rounded, color: Colors.teal.shade700, size: 28),
                      items: empShifts.map((shift) {
                        return DropdownMenuItem<String>(
                          value: shift['id'],
                          child: Text(
                            '${shift['name']} (${shift['date']})',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: isShiftSelectable
                          ? (value) async {
                              if (value != null) {
                                final selectedShiftName = empShifts.firstWhere(
                                  (shift) => shift['id'] == value,
                                  orElse: () => {'name': 'Unknown'},
                                )['name'];
                                bool confirmed = await _showConfirmationDialog(
                                  context,
                                  'Are you sure you want to select the shift: $selectedShiftName?',
                                );
                                if (confirmed) {
                                  setState(() {
                                    selectedShift = value;
                                  });
                                }
                              }
                            }
                          : null,
                      disabledHint: Text(
                        selectedShift != null
                            ? empShifts.firstWhere(
                                (s) => s['id'] == selectedShift,
                                orElse: () => {'name': 'General Shift'},
                              )['name']
                            : 'Shift selection unavailable',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckIn &&
                                  !isProcessing &&
                                  selectedShift != null &&
                                  empShifts.any(
                                    (shift) =>
                                        shift['id'] == selectedShift &&
                                        shift['isActive'] as bool,
                                  ))
                              ? () async {
                                final selectedShiftData = empShifts.firstWhere(
                                  (shift) => shift['id'] == selectedShift,
                                  orElse: () => {'isActive': false},
                                );
                                if (selectedShiftData['isActive'] as bool) {
                                  await handleCheckIn();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select an active shift.',
                                      ),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckIn &&
                                    !isProcessing &&
                                    selectedShift != null &&
                                    empShifts.any(
                                      (shift) =>
                                          shift['id'] == selectedShift &&
                                          shift['isActive'] as bool,
                                    ))
                                ? 1.0
                                : 0.4,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1AEA24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Icon(
                                Icons.login,
                                size: 36,
                                color: Colors.black,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                checkInTime,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Check In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckOut && !isProcessing)
                              ? () async {
                                await handleCheckOut();
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckOut && !isProcessing) ? 1.0 : 0.4,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Icon(
                                Icons.logout,
                                size: 36,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                checkOutTime,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Check Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                'Shifts Working Time: $totalWorkingHours',
                style: const TextStyle(color: Color(0xFF121111), fontSize: 16),
              ),
            ),
          ],
        ),
      ),
      );
      }
      switch (index) {
        case 1:
          return LeaveScreen(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId,
            deviceSerialNumber: widget.deviceSerialNumber,
            isAdmin: isAdminUser,
          );
        case 2:
          return Requests(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId,
            deviceSerialNumber: widget.deviceSerialNumber,
            isAdmin: isAdminUser,
          );
        case 3:
          return ExpensesScreen(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId,
            deviceSerialNumber: widget.deviceSerialNumber,
            isAdmin: isAdminUser,
          );
        case 4:
          return MoreScreen(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId,
            deviceSerialNumber: widget.deviceSerialNumber,
            isAdmin: isAdminUser,
          );
        default:
          return Container();
      }
    }

    return Stack(
      children: [
        mainContent(),
        if (isProcessing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.black12),
            ),
          ),
      ],
    );
  }
}
