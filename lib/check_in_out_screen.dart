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
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'admin_page.dart';
import 'attendance_history_screen.dart';
import 'leave_screen.dart';
import 'login_screen.dart';
import 'ot_late_request_screen.dart';
import 'requests.dart';
import 'expenses_screen.dart';
import 'vhs_expenses_screen.dart';
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Inside callbackDispatcher()  â†’  Workmanager task
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == finalLocationTask) {
      debugPrint(
        'Workmanager task executed at ${DateTime.now().toIso8601String()}',
      );

      try {
        final prefs = await SharedPreferences.getInstance();
        final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
        if (!isCheckedIn) {
          debugPrint('Not checked in - skipping');
          return true;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final lastSentMs = prefs.getInt('last_location_sent_ms') ?? 0;
        if (nowMs - lastSentMs < 9 * 60 * 1000) {
          debugPrint('Workmanager: duplicate skipped');
          return true;
        }
        await prefs.setInt('last_location_sent_ms', nowMs);

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );

        final payload = {
          'auth_token': inputData?['authToken'] ?? '',
          'emp_id': inputData?['empId'] ?? '',
          'shift_id': inputData?['shiftId'] ?? '',
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
          'device_serial_number': inputData?['deviceSerialNumber'] ?? '',
        };

        final connectivityResults = await Connectivity().checkConnectivity();
        if (connectivityResults.isNotEmpty &&
            !connectivityResults.contains(ConnectivityResult.none)) {
          final response = await ApiService.sendLocationUpdate(payload);

          final data = jsonDecode(response.body);
          debugPrint('Workmanager Response: $data');

          if (response.statusCode == 200 && data['status'] == 'ok') {
            // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ NEW: Show notification on every successful send â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final bgPlugin = FlutterLocalNotificationsPlugin();
            await bgPlugin.initialize(
              const InitializationSettings(
                android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              ),
            );

            _backgroundLocationSendCount++; // optional counter

            final action = data['action']?.toString() ?? '';
            String notificationBody;
            if (data['auto_checkout'] == true) {
              notificationBody =
                  'Auto-checkout triggered!\nTotal hours: ${data['cumulative_working_hours'] ?? 'N/A'}';
              await prefs.setBool('is_checked_in', false);
              await Workmanager().cancelByUniqueName(finalLocationTask);
            } else if (action == 'wait_for_approval') {
              notificationBody = 'Location recorded — pending shift approval';
            } else {
              notificationBody =
                  'Background location sent (${_backgroundLocationSendCount}x today)';
            }

            await bgPlugin.show(
              DateTime.now().millisecondsSinceEpoch % 10000, // unique id
              data['auto_checkout'] == true
                  ? 'Auto Checkout'
                  : 'Attendance Tracking',
              notificationBody,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'attendance_channel_id',
                  'Attendance Notifications',
                  channelDescription:
                      'Background location & attendance updates',
                  importance: Importance.defaultImportance,
                  priority: Priority.defaultPriority,
                  ticker: 'Location sent',
                ),
              ),
            );

            // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

            if (data['auto_checkout'] == true) {
              debugPrint('Auto-checkout done â†’ stopping task');
              return true;
            }
            return true;
          } else {
            // your existing error handling...
            await _storePendingLocation(payload, prefs);
            return false;
          }
        } else {
          debugPrint('No internet â†’ storing pending');
          await _storePendingLocation(payload, prefs);
          return false;
        }
      } catch (e) {
        debugPrint('Workmanager error: $e');
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
  debugPrint('Workmanager stored pending location: $payload');
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('Background service started');

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      debugPrint('Setting as foreground service');
      service.setAsForegroundService();
    });

    service.on('stop').listen((event) async {
      debugPrint('Received stop command from main app - shutting down service');
      final prefs = await SharedPreferences.getInstance();
      final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
      if (isCheckedIn) {
        debugPrint(
          'User is still checked-in → background tracking will rely on Workmanager',
        );
      }
      service.stopSelf();
    });
  }

  // Load initial state from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  bool isCheckedIn = prefs.getBool('is_checked_in') ?? false;
  String? empId = prefs.getString('empId');
  String? authToken = prefs.getString('authToken');
  String? deviceSerialNumber = prefs.getString('deviceSerialNumber');
  String? selectedShift = prefs.getString('selected_shift');

  // Initialize notifications in background isolate
  final bgPlugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await bgPlugin.initialize(const InitializationSettings(android: androidInit));

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'attendance_channel_id',
    'Attendance Notifications',
    description: 'Notifications for attendance events',
    importance: Importance.max,
    playSound: true,
  );
  await bgPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  Timer? bgLocationTimer;

  void startBgLocationTimer() {
    bgLocationTimer?.cancel();

    bgLocationTimer = Timer.periodic(const Duration(seconds: 600), (
      timer,
    ) async {
      if (!isCheckedIn) {
        debugPrint('Background: User not checked in → stopping location timer');
        timer.cancel();
        bgLocationTimer = null;
        return;
      }

      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final lastSentMs = prefs.getInt('last_location_sent_ms') ?? 0;
        if (nowMs - lastSentMs < 9 * 60 * 1000) {
          debugPrint('BG service: duplicate skipped');
          return;
        }
        await prefs.setInt('last_location_sent_ms', nowMs);

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );

        final payload = {
          'auth_token': authToken ?? '',
          'emp_id': empId ?? '',
          'shift_id': selectedShift ?? '',
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
          'device_serial_number': deviceSerialNumber ?? '',
        };

        final response = await ApiService.sendLocationUpdate(payload);
        final data = jsonDecode(response.body);

        if (data['auto_checkout'] == true) {
          debugPrint('Auto-checkout triggered in background');
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

          isCheckedIn = false;
          await prefs.setBool('is_checked_in', false);
          await prefs.setString('selected_shift', '');
          timer.cancel();
          bgLocationTimer = null;
        }
      } catch (e) {
        debugPrint('Background location update failed silently: $e');
      }
    });
  }

  // Start timer on initial startup if checked in
  if (isCheckedIn) {
    startBgLocationTimer();
  }

  // Listen for state updates from main app
  service.on('updateState').listen((event) async {
    if (event != null) {
      final wasCheckedIn = isCheckedIn;
      isCheckedIn = event['isCheckedIn'] ?? isCheckedIn;
      empId = event['empId'] ?? empId;
      authToken = event['authToken'] ?? authToken;
      deviceSerialNumber = event['deviceSerialNumber'] ?? deviceSerialNumber;
      selectedShift = event['selectedShift'] ?? selectedShift;

      debugPrint('Background: State updated → isCheckedIn: $isCheckedIn');

      await prefs.setBool('is_checked_in', isCheckedIn);
      await prefs.setString('selected_shift', selectedShift ?? '');

      if (isCheckedIn && (!wasCheckedIn || bgLocationTimer == null)) {
        startBgLocationTimer();
      } else if (!isCheckedIn && bgLocationTimer != null) {
        bgLocationTimer?.cancel();
        bgLocationTimer = null;
      }
    }
  });

  debugPrint('Background service fully initialized and running');
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
  if (!isCheckedIn) {
    await Workmanager().cancelByUniqueName(finalLocationTask);
    debugPrint(
      'Canceled Workmanager task in iOS background as user is not checked in',
    );
    return true;
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final storedAuthToken = prefs.getString('authToken') ?? '';
    final storedEmpId = prefs.getString('empId') ?? '';
    final storedDeviceSerial = prefs.getString('deviceSerialNumber') ?? '';
    final storedShiftId = prefs.getString('selected_shift') ?? '';

    final payload = {
      'auth_token': storedAuthToken,
      'emp_id': storedEmpId,
      'shift_id': storedShiftId,
      'latitude': position.latitude.toString(),
      'longitude': position.longitude.toString(),
      'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'device_serial_number': storedDeviceSerial,
    };

    final connectivityResults = await Connectivity().checkConnectivity();
    final isConnected =
        connectivityResults.isNotEmpty &&
        !connectivityResults.contains(ConnectivityResult.none);
    if (isConnected) {
      try {
        final response = await ApiService.sendLocationUpdate(payload);
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok' && data['auto_checkout'] == true) {
          await prefs.setBool('is_checked_in', false);
          await prefs.setString('selected_shift', '');
          await Workmanager().cancelByUniqueName(finalLocationTask);
        }
      } catch (e) {
        await _storePendingLocation(payload, prefs);
      }
    } else {
      await _storePendingLocation(payload, prefs);
    }

    await Workmanager().registerPeriodicTask(
      finalLocationTask,
      finalLocationTask,
      frequency: const Duration(minutes: 15),
      inputData: {
        'authToken': storedAuthToken,
        'empId': storedEmpId,
        'shiftId': storedShiftId,
        'deviceSerialNumber': storedDeviceSerial,
      },
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint('Scheduled Work manager periodic task for iOS background');
  } catch (e) {
    debugPrint('iOS background location update failed: $e');
    final storedAuthToken = prefs.getString('authToken') ?? '';
    final storedEmpId = prefs.getString('empId') ?? '';
    final storedDeviceSerial = prefs.getString('deviceSerialNumber') ?? '';
    final storedShiftId = prefs.getString('selected_shift') ?? '';
    await _storePendingLocation({
      'auth_token': storedAuthToken,
      'emp_id': storedEmpId,
      'shift_id': storedShiftId,
      'latitude': '0.0',
      'longitude': '0.0',
      'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'device_serial_number': storedDeviceSerial,
    }, prefs);
  }
  return true;
}

class CheckInOutScreen extends StatefulWidget {
  final String empName;
  final String empId;
  final String authToken;
  final String deviceSerialNumber;
  final String companyId;
  final String companyLogo;
  final bool isAdmin;

  const CheckInOutScreen({
    super.key,
    required this.empName,
    required this.empId,
    required this.authToken,
    required this.deviceSerialNumber,
    required this.companyId,
    this.companyLogo = '',
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
  bool _isSessionDialogShowing = false;
  bool _isFetching = false;

  // Attendance calendar state
  int _calMonth = DateTime.now().month;
  int _calYear = DateTime.now().year;
  Map<int, String> _calData = {};
  bool _calLoading = false;

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  StreamSubscription<Position>? positionStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isConnected = true;
  bool _isNoInternetDialogShowing = false;
  bool isAdminUser = false;
  String _companyLogoUrl = "";
  DateTime? _lastAutoRefresh;

  // VHS detected by logo URL keywords (visakha /
  //vhs / hospital / vhc)
  bool get _isVHS {
    final logo = _companyLogoUrl.toLowerCase();
    return logo.contains('vhs') ||
        logo.contains('visakha') ||
        logo.contains('hospital') ||
        logo.contains('vhc');
  }

  @override
  void initState() {
    super.initState();
    _companyLogoUrl =
        widget
            .companyLogo; // set immediately — don't wait for SharedPreferences
    WidgetsBinding.instance.addObserver(this);
    updateTime();
    // Only need minute precision for the 9:15 AM reminder check
    clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => updateTime(),
    );
    _initNotifications();
    _initializeWorkmanager();
    _initializeConnectivityMonitoring();
    _loadShiftsAsync();
    _loadCompanyLogo();
    _fetchCalendarData();
  }

  Future<void> _loadCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final logo = prefs.getString("companyLogo") ?? "";
    debugPrint(
      '🏢 companyLogo URL: $logo  |  isVHS: ${logo.toLowerCase().contains('vhs') || logo.toLowerCase().contains('visakha') || logo.toLowerCase().contains('hospital') || logo.toLowerCase().contains('vhc')}',
    );
    if (mounted) {
      _safeSetState(() => _companyLogoUrl = logo);
    }
  }

  Future<void> _fetchCalendarData() async {
    _safeSetState(() => _calLoading = true);
    try {
      final response = await ApiService.fetchAttendanceHistory(
        authToken: widget.authToken,
        month: _calMonth,
        year: _calYear,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final daysMap = data['days'] as Map<String, dynamic>? ?? {};
        final Map<int, String> result = {};
        daysMap.forEach((key, value) {
          final dayNum = int.tryParse(key.replaceAll('day', '')) ?? 0;
          if (dayNum > 0)
            result[dayNum] = (value['status'] ?? 'A').toString().toUpperCase();
        });
        _safeSetState(() => _calData = result);
      }
    } catch (_) {}
    _safeSetState(() => _calLoading = false);
  }

  Color _calStatusColor(String? code, {bool isSunday = false}) {
    switch (code) {
      case 'P':
        return Colors.green.shade500;
      case 'A':
        return Colors.red.shade400;
      case 'L':
        return Colors.yellow.shade700; // Leave = yellow
      case 'OT':
      case 'LT':
      case 'LATE':
        return Colors.orange.shade500; // Late/OT = orange
      case 'H':  // Half Day (API code H)
      case 'HD':
      case 'CO':
      case 'COMPOFF':
        return Colors.orange.shade400; // Half Day / Comp Off = orange
      case 'O':
        return Colors.red.shade100; // Holiday = same bg as Sunday
      case 'WO':
        return Colors.purple.shade200;
      default:
        return isSunday ? Colors.red.shade100 : Colors.transparent;
    }
  }

  Widget _calLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _calSummaryItem(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    // Dart weekday: 1=Mon..7=Sun; convert to 0=Sun..6=Sat
    final firstWeekday = firstDay.weekday == 7 ? 0 : firstDay.weekday;
    final monthName = DateFormat('MMMM yyyy').format(firstDay);
    final totalCells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;

    // Summary counts
    final presentCount = _calData.values.where((c) => c == 'P').length;
    final absentCount = _calData.values.where((c) => c == 'A').length;
    final leaveCount = _calData.values.where((c) => c == 'L').length;
    final lateCount =
        _calData.values
            .where((c) => c == 'OT' || c == 'LT' || c == 'LATE')
            .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month navigator
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: () {
                    _safeSetState(() {
                      if (_calMonth == 1) {
                        _calMonth = 12;
                        _calYear--;
                      } else {
                        _calMonth--;
                      }
                      _calData = {};
                    });
                    _fetchCalendarData();
                  },
                ),
                Text(
                  monthName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: () {
                    _safeSetState(() {
                      if (_calMonth == 12) {
                        _calMonth = 1;
                        _calYear++;
                      } else {
                        _calMonth++;
                      }
                      _calData = {};
                    });
                    _fetchCalendarData();
                  },
                ),
              ],
            ),
          ),
          // Summary count row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _calSummaryItem('Present', presentCount, Colors.green.shade500),
                const SizedBox(width: 6),
                _calSummaryItem('Absent', absentCount, Colors.red.shade400),
                const SizedBox(width: 6),
                _calSummaryItem('Leave', leaveCount, Colors.yellow.shade700),
                const SizedBox(width: 6),
                _calSummaryItem('Late', lateCount, Colors.orange.shade500),
              ],
            ),
          ),
          const Divider(height: 10, thickness: 0.5),
          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                ...[
                  ' Su',
                  'Mo',
                  'Tu',
                  'We',
                  'Th',
                  'Fr',
                  'Sa',
                ].asMap().entries.map(
                  (e) => Expanded(
                    child: Center(
                      child: Text(
                        e.value.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color:
                              e.key == 0
                                  ? Colors.blueGrey.shade400
                                  : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Calendar grid
          _calLoading
              ? const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
              : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 2,
                    childAspectRatio: 1,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (_, i) {
                    final dayNum = i - firstWeekday + 1;
                    if (dayNum <= 0 || dayNum > daysInMonth) {
                      return const SizedBox();
                    }
                    final isToday =
                        now.year == _calYear &&
                        now.month == _calMonth &&
                        now.day == dayNum;
                    final isFuture = DateTime(
                      _calYear,
                      _calMonth,
                      dayNum,
                    ).isAfter(DateTime(now.year, now.month, now.day));
                    final code = _calData[dayNum];

                    // Company-aware Week Off / Sunday detection
                    // VHS (company 2): week off is any day the API marks WO
                    // Eltrive (others): column 0 = Sunday (auto-detected)
                    final isWOByApi = code == 'WO';
                    final isHoliday = code == 'O';
                    final isEltriveSunday = !_isVHS && (i % 7) == 0; // Sunday light-red: Company 1 only
                    final showWSymbol =
                        isWOByApi && !isEltriveSunday; // VHS WO only
                    final showHSymbol =
                        isHoliday && !isEltriveSunday; // Holiday on non-Sunday
                    final showSSymbol = isEltriveSunday; // Sunday ALWAYS S

                    Color bg;
                    if (isFuture) {
                      bg =
                          isEltriveSunday
                              ? Colors.red.shade50
                              : isWOByApi
                              ? Colors.purple.shade50
                              : isHoliday
                              ? Colors.red.shade50
                              : Colors.transparent;
                    } else if (isEltriveSunday) {
                      // Sunday is ALWAYS light-red — ignore API status (P/A/etc.)
                      bg = Colors.red.shade100;
                    } else {
                      bg = _calStatusColor(code, isSunday: false);
                    }

                    // Text colour based on background
                    // Text colour: dark on light bg, white on dark bg
                    Color textColor;
                    if (isEltriveSunday) {
                      textColor = Colors.red.shade700;
                    } else if (isWOByApi) {
                      textColor = Colors.purple.shade700;
                    } else if (isHoliday || bg == Colors.red.shade100) {
                      textColor = Colors.red.shade700;
                    } else if (bg == Colors.yellow.shade700 ||
                        bg == Colors.orange.shade400 ||
                        bg == Colors.transparent) {
                      textColor = Colors.black87;
                    } else {
                      textColor =
                          Colors.white; // dark bg: green, red, blue, orange
                    }

                    // Symbol to show: W=WeekOff, H=Holiday, S=Sunday, else null
                    final symbol =
                        showWSymbol
                            ? 'W'
                            : (showHSymbol ? 'H' : (showSSymbol ? 'S' : null));

                    return GestureDetector(
                      onTap:
                          isFuture
                              ? null
                              : () {
                                final tappedDate = DateTime(
                                  _calYear,
                                  _calMonth,
                                  dayNum,
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => AttendanceHistoryScreen(
                                          empId: widget.empId,
                                          authToken: widget.authToken,
                                          empName: widget.empName,
                                          initialDate: tappedDate,
                                        ),
                                  ),
                                );
                              },
                      child: Container(
                        decoration: BoxDecoration(
                          color: bg,
                          shape: BoxShape.circle,
                          border:
                              isToday
                                  ? Border.all(
                                    color: Colors.teal.shade700,
                                    width: 2,
                                  )
                                  : null,
                        ),
                        child:
                            symbol != null
                                // Sunday or Week-Off: show only the letter (S or W)
                                ? Center(
                                  child: Text(
                                    symbol,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                )
                                : Center(
                                  child: Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                      ),
                    );
                  },
                ),
              ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _calLegendDot(Colors.green.shade500, 'Present'),
                _calLegendDot(Colors.red.shade400, 'Absent'),
                _calLegendDot(Colors.yellow.shade700, 'Leave'),
                _calLegendDot(Colors.orange.shade500, 'Late / OT'),
                _calLegendDot(Colors.orange.shade400, 'Half Day / CO'),
                _calLegendDot(Colors.red.shade100, 'Holiday (H)'),
                if (_isVHS)
                  _calLegendDot(Colors.purple.shade200, 'Week Off (W)')
                else
                  _calLegendDot(Colors.red.shade100, 'Sunday (S)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the correct logo widget for the logged-in employee's company.
  /// - If the server provided a logo URL â†’ show it (network image).
  /// - Eltrive companies (ID 1 or 2) â†’ show Eltrive logo asset.
  /// - All other companies (VHS, etc.) â†’ show VHS logo asset.
  Widget _companyLogoWidget() {
    // company_id "1" = Eltrive, "2" = VHS hospital
    final localAsset =
        _isVHS ? 'assets/vhs_logo.png' : 'assets/eltrive_plan.png';

    if (_companyLogoUrl.isNotEmpty) {
      return Image.network(
        _companyLogoUrl,
        height: 80,
        fit: BoxFit.contain,
        errorBuilder:
            (_, __, ___) =>
                Image.asset(localAsset, height: 80, fit: BoxFit.contain),
      );
    }
    return Image.asset(localAsset, height: 80, fit: BoxFit.contain);
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

    const AndroidNotificationChannel foregroundChannel =
        AndroidNotificationChannel(
          'attendance_foreground',
          'Attendance Foreground Service',
          description: 'Permanent notification for active attendance tracking',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
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
      debugPrint('Canceled stray Workmanager tasks on app start');
    }
  }

  void _initializeConnectivityMonitoring() {
    // Initial connectivity check
    _checkInternetConnectivity().then((isConnected) {
      _safeSetState(() {
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
      _safeSetState(() {
        _isConnected = isConnected;
      });
      if (!isConnected && !_isNoInternetDialogShowing) {
        _showNoInternetDialog();
      } else if (isConnected && _isNoInternetDialogShowing) {
        if (mounted) Navigator.of(context).pop();
        _isNoInternetDialogShowing = false;
        // Retry critical operations
        await _loadShiftsAsync();
      }
    });
  }

  Future<bool> _checkInternetConnectivity() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.isEmpty ||
        connectivityResults.contains(ConnectivityResult.none)) {
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
    debugPrint('AppLifecycleState changed: $state');
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed. Auto-refreshing shifts and status...');
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
      if (!isCheckedIn) {
        await Workmanager().cancelByUniqueName(finalLocationTask);
        debugPrint('Canceled Workmanager task: User is not checked in');
        return;
      }

      // Cancel any existing task first
      await Workmanager().cancelByUniqueName(finalLocationTask);

      // Register new periodic task
      await Workmanager().registerPeriodicTask(
        finalLocationTask,
        finalLocationTask,
        frequency: const Duration(
          minutes: 15,
        ), // Android minimum reliable interval
        initialDelay: const Duration(
          seconds: 30,
        ), // Start soon after check-in/kill
        inputData: {
          'authToken': widget.authToken,
          'empId': widget.empId,
          'shiftId':
              selectedShift ?? '', // â† FIX: Prevent null â†’ wrong type error
          'deviceSerialNumber': widget.deviceSerialNumber,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      debugPrint(
        'Successfully scheduled Workmanager periodic task (every ~15 min)',
      );
    } catch (e) {
      debugPrint('Failed to schedule Workmanager task: $e');
      _handleError('Background location scheduling failed', e);

      // Mark for retry on next app open
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('retry_final_location', true);
    }
  }

  Future<void> _requestBatteryOptimization() async {
    const String prefKeyShown = 'battery_prompt_shown_once';
    final prefs = await SharedPreferences.getInstance();

    // Already granted - nothing to do
    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      return;
    }

    // Already shown once on first install - never show again
    if (prefs.getBool(prefKeyShown) == true) {
      return;
    }

    // Mark as shown so it never appears again
    await prefs.setBool(prefKeyShown, true);

    if (!mounted) return;

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Allow Background Location'),
            content: const Text(
              'To track your attendance accurately even when the app is closed or minimized, please allow this app to run in the background without battery restrictions. Tap Allow on the next screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Allow'),
              ),
            ],
          ),
    );

    if (granted == true) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  void _autoSelectShift() {
    if (selectedShift != null && selectedShift!.isNotEmpty) {
      debugPrint(
        'Auto-select: Shift already selected ($selectedShift), preserving user manual selection.',
      );
      return;
    }

    if (empShifts.isEmpty) {
      debugPrint('Auto-select: empShifts is empty, cannot auto-select.');
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
        return name.contains('general') ||
            name.contains('gen') ||
            name.contains('day');
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
      if (targetShiftType == 'General' &&
          (name.contains('general') ||
              name.contains('gen') ||
              name.contains('day'))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'A' &&
          (name.contains('shift a') ||
              name.contains('a shift') ||
              name.startsWith('a ') ||
              name.contains(': a') ||
              name.contains(' a '))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'B' &&
          (name.contains('shift b') ||
              name.contains('b shift') ||
              name.startsWith('b ') ||
              name.contains(': b') ||
              name.contains(' b '))) {
        matchedShift = shift;
        break;
      } else if (targetShiftType == 'C' &&
          (name.contains('shift c') ||
              name.contains('c shift') ||
              name.startsWith('c ') ||
              name.contains(': c') ||
              name.contains(' c '))) {
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

    _safeSetState(() {
      selectedShift = matchedShift!['id'];
    });
    debugPrint(
      'Auto-detected and selected shift: ${matchedShift['name']} (ID: $selectedShift)',
    );
  }

  Future<void> _loadShiftsAsync({bool force = false}) async {
    // Prevent repeated auto-triggers within 2 minutes
    if (!force) {
      final now = DateTime.now();
      if (_lastAutoRefresh != null && now.difference(_lastAutoRefresh!).inSeconds < 120) {
        return;
      }
    }
    _lastAutoRefresh = DateTime.now();
    try {
      _safeSetState(() => isShiftsLoading = true);
      await _initializeApp();
      if (!_isConnected) {
        if (mounted && !_isNoInternetDialogShowing) {
          _showNoInternetDialog();
        }
        _safeSetState(() => isShiftsLoading = false);
        return;
      }
      await _syncPendingLocations();
      _safeSetState(() => isShiftsLoading = false);
    } catch (_) {
      _safeSetState(() => isShiftsLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clockTimer.cancel();
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
      final response = await http
          .get(Uri.parse('https://hrm.eltrive.com/api/app-version'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion =
            int.tryParse(data['latest_version_code']?.toString() ?? '') ?? 0;
        final forceUpdate = data['force_update'] as bool? ?? false;
        final storeUrl =
            data['play_store_url']?.toString() ??
            'https://play.google.com/store/apps/details?id=com.ELT_EMP.as_f';

        const int localAppVersionCode = 12;

        if (latestVersion > localAppVersionCode && forceUpdate) {
          _showForcedUpdateDialog(storeUrl);
        }
      }
    } catch (e) {
      debugPrint(
        'Update check bypassed: $e',
      ); // Fails silently to prevent locking users out if endpoint isn't ready
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
                Icon(
                  Icons.system_update_rounded,
                  color: Colors.teal.shade700,
                  size: 28,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Update Required',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
                    icon: const Icon(
                      Icons.shopping_bag_rounded,
                    ), // Generic shopping/store bag icon
                    label: const Text(
                      'UPDATE NOW',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onPressed: () async {
                      final url = Uri.parse(storeUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
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

    debugPrint('DEBUG ADMIN CHECK START:');
    debugPrint('  - widget.empId: "${widget.empId}"');
    debugPrint('  - storedEmpId in prefs: "$storedEmpId"');
    debugPrint('  - userRole in prefs: "${prefs.getString('userRole')}"');
    debugPrint('  - savedIsAdmin in prefs: "${prefs.getBool('isAdminUser')}"');

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
      final savedFcm = prefs.getString('fcm_token') ?? '';
      final savedIsAdmin = prefs.getBool('isAdminUser') ?? false;
      await prefs.clear();
      await prefs.setString(_prefKeyEmpId, widget.empId);
      await prefs.setString('last_opened_date', todayStr);
      await prefs.setString('authToken', widget.authToken);
      await prefs.setString('deviceSerialNumber', widget.deviceSerialNumber);
      if (savedLogo.isNotEmpty) await prefs.setString('companyLogo', savedLogo);
      if (savedRole.isNotEmpty) await prefs.setString('userRole', savedRole);
      if (savedFcm.isNotEmpty) await prefs.setString('fcm_token', savedFcm);
      if (savedIsAdmin) await prefs.setBool('isAdminUser', true);
      debugPrint('Cleared SharedPreferences for new empId: ${widget.empId}');
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
        debugPrint(
          'New day detected ($todayStr != $lastOpenedDate). Resetting daily check-in/out state.',
        );
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
    _safeSetState(() {
      isAdminUser =
          widget.isAdmin ||
          userRole == 'admin' ||
          widget.empId == '0' ||
          widget.empId == 'admin' ||
          savedIsAdmin;
    });
    debugPrint('DEBUG ADMIN CHECK END:');
    debugPrint('  - calculated isAdminUser: $isAdminUser');
    debugPrint('  - userRole: "$userRole"');
    debugPrint('  - savedIsAdmin: $savedIsAdmin');
    if (isAdminUser) {
      await prefs.setString('userRole', 'admin');
      await prefs.setBool('isAdminUser', true);
    }

    debugPrint(
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
        'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        'device_serial_number': widget.deviceSerialNumber,
      };
      if (_isConnected) {
        await _sendLocationUpdateWithRetry(payload, prefs);
        debugPrint('Sent final location update on app termination');
      } else {
        await _storePendingLocation(payload, prefs);
        debugPrint('Stored final location for later sync');
      }
    } catch (e) {
      debugPrint('Failed to send final location update: $e');
      _handleError('Could not send final location update', e);
      final prefs = await SharedPreferences.getInstance();
      await _storePendingLocation({
        'auth_token': widget.authToken,
        'emp_id': widget.empId,
        'shift_id': selectedShift,
        'latitude': '0.0',
        'longitude': '0.0',
        'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
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
    debugPrint(
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
        debugPrint('Failed to sync pending location: $e');
        continue;
      }
    }
    await prefs.setStringList(_prefKeyPendingLocations, []);
    debugPrint('Cleared pending locations after sync');
  }

  Future<Map<String, dynamic>> _sendLocationUpdateWithRetry(
    Map<String, dynamic> payload,
    SharedPreferences prefs,
  ) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await ApiService.sendLocationUpdate(payload);
        final data = jsonDecode(response.body);
        debugPrint('Location Update Response: $data');

        if (data['status'] == 'ok') {
          // ── Auto-checkout triggered by server ─────────────────────────
          if (data['auto_checkout'] == true) {
            _safeSetState(() {
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
            await _showNotification(
              title: 'Auto Checkout',
              body:
                  'Server triggered auto-checkout. Total: ${data['cumulative_working_hours']}',
            );
          }

          // ── Pending approval action ────────────────────────────────────
          // action = "wait_for_approval" means a checkout/OT request is
          // pending approval; location is recorded successfully in the DB.
          final action = data['action']?.toString() ?? '';
          if (action == 'wait_for_approval') {
            debugPrint('Location sent — pending approval for this shift.');
          }

          // ── GPS fence distance ─────────────────────────────────────────
          // distance_from_fence > 0 means the employee is outside the
          // approved zone; the backend decides whether to allow check-in.
          final fenceDistance = (data['distance_from_fence'] ?? 0).toDouble();
          if (fenceDistance > 500) {
            debugPrint(
              'Employee is ${fenceDistance.toStringAsFixed(0)}m from approved location.',
            );
          }
        }
        return data; // Return data for background handling
      } catch (e) {
        debugPrint('Attempt $attempt failed: $e');
        if (attempt == 3) {
          await _storePendingLocation(payload, prefs);
          debugPrint('Max retries reached, stored location for later sync');
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
        debugPrint(
          'Background location permission denied - continuing in foreground mode silently',
        );
      }
    }

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true, // â† important
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: 'attendance_foreground', // new channel
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Persistent notification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        initialNotificationTitle: 'Attendance Active',
        initialNotificationContent:
            'Location is being tracked for check-in / check-out',
        // Show this notification permanently while checked-in
        foregroundServiceNotificationId: 1001,
        foregroundServiceTypes: [AndroidForegroundType.location],
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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30,
      ),
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
      'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'device_serial_number': deviceSerialNumber,
    };
    if (_isConnected) {
      await _sendLocationUpdateWithRetry(payload, prefs);
    } else {
      await _storePendingLocation(payload, prefs);
    }
  }

  void _startLocationSending() {
    if (locationSendTimer != null) {
      return; // Already running, do not recreate or send immediately
    }
    if (isCheckedIn) {
      locationSendTimer = Timer.periodic(const Duration(seconds: 600), (
        _,
      ) async {
        try {
          final dedupePrefs = await SharedPreferences.getInstance();
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final lastSentMs = dedupePrefs.getInt('last_location_sent_ms') ?? 0;
          if (nowMs - lastSentMs < 9 * 60 * 1000) {
            return;
          }
          await dedupePrefs.setInt('last_location_sent_ms', nowMs);

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
    }
  }

  void _stopLocationSending() {
    locationSendTimer?.cancel();
    locationSendTimer = null;
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

  bool _isAuthError(dynamic message) {
    if (message == null) return false;
    final msg = message.toString().toLowerCase();
    return msg.contains('invalid token') ||
        msg.contains('token invalid') ||
        msg.contains('session expired') ||
        msg.contains('expired token') ||
        msg.contains('employee not found') ||
        msg.contains('code mismatch');
  }

  void _handleError(String message, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('$message: $error${stackTrace != null ? '\n$stackTrace' : ''}');
    if (_isAuthError(error) || _isAuthError(message)) {
      return; // Skip showing UI error indicators for token expiry/mismatch
    }
    if (mounted) {
      if (isAdminUser) {
        return; // Don't show error SnackBars or notifications for admins
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$message: ${error.toString().split(':').last.trim()}'),
        ),
      );
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
                    _safeSetState(() => _isConnected = true);
                    await _loadShiftsAsync(force: true);
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
    final defaultsDateStr =
        '${nowForDefaults.year}-${nowForDefaults.month.toString().padLeft(2, '0')}-${nowForDefaults.day.toString().padLeft(2, '0')}';

    final List<Map<String, dynamic>> defaultShifts = [
      {
        'id': '1',
        'name': 'General Shift : 09:00 AM - 05:00 PM',
        'startTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          9,
          0,
        ),
        'endTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          17,
          0,
        ),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '2',
        'name': 'A Shift : 06:00 AM - 02:00 PM',
        'startTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          6,
          0,
        ),
        'endTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          14,
          0,
        ),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '3',
        'name': 'B Shift : 02:00 PM - 10:00 PM',
        'startTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          14,
          0,
        ),
        'endTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          22,
          0,
        ),
        'isActive': true,
        'date': defaultsDateStr,
      },
      {
        'id': '4',
        'name': 'C Shift : 10:00 PM - 06:00 AM',
        'startTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          22,
          0,
        ),
        'endTime': DateTime(
          nowForDefaults.year,
          nowForDefaults.month,
          nowForDefaults.day,
          6,
          0,
        ).add(const Duration(days: 1)),
        'isActive': true,
        'date': defaultsDateStr,
      },
    ];

    _safeSetState(() {
      empShifts = defaultShifts;
      isShiftSelectable = true;
    });

    if (!isCheckedIn) {
      _autoSelectShift();
    }
  }

  Future<void> fetchShifts() async {
    if (_isFetching) return;
    if (!_isConnected) {
      _handleError('No internet connection', Exception('Please try again'));
      if (!_isNoInternetDialogShowing) {
        _showNoInternetDialog();
      }
      return;
    }
    _isFetching = true;
    tz_data.initializeTimeZones();
    final ist = tz.getLocation('Asia/Kolkata');
    _safeSetState(() => isShiftsLoading = true);
    try {
      final response = await ApiService.fetchShifts(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      debugPrint('Shifts API Response: $data');
      if (response.statusCode == 200 && data['status'] == 'success') {
        final List shiftsData = data['shifts'] ?? [];
        final now = tz.TZDateTime.now(ist);
        final today = DateTime(now.year, now.month, now.day);
        debugPrint('Current Time (IST): $now, Today: $today');
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
                  endHour > 12 ? endHour - 12 : (endHour == 0 ? 12 : endHour);
              final overnight = endTime.day != startTime.day;
              displayTime =
                  '$start12:${startMin.toString().padLeft(2, '0')} $startPeriod - '
                  '$end12:${endMin.toString().padLeft(2, '0')} $endPeriod${overnight ? ' (Next Day)' : ''}';
            } else {
              debugPrint(
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

        _safeSetState(() {
          empShifts = newShifts;
          // Selectable only when there are multiple shifts
          isShiftSelectable = newShifts.length > 1;
        });

        if (!isCheckedIn) {
          if (newShifts.length == 1) {
            // Only one shift assigned — auto-select immediately, no user action needed
            _safeSetState(() => selectedShift = newShifts[0]['id']);
            debugPrint('Single shift auto-selected: ${newShifts[0]['name']}');
          } else {
            _autoSelectShift();
          }
        }
      } else {
        // Any non-success response (auth, server error, etc.) â€” load defaults silently
        _populateDefaultShifts();
        debugPrint('fetchShifts failed silently: ${data['message']}');
      }
    } catch (e) {
      _populateDefaultShifts();
      debugPrint('fetchShifts exception: $e');
    } finally {
      _isFetching = false;
      _safeSetState(() => isShiftsLoading = false);
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
      _safeSetState(() => isStatusLoading = true);
      final response = await ApiService.fetchStatus(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      debugPrint('Status API Response: $data');
      if (response.statusCode == 200 && data['status'] == 'success') {
        String displayTime = 'General Shift';
        DateTime? startTime;
        DateTime? endTime;
        final shiftTime = data['shift_time']?.toString() ?? '-';
        final shiftId = data['shift_id']?.toString() ?? '';
        final shiftNameRaw = data['shift_name']?.toString() ?? '';
        final shiftName =
            shiftNameRaw.trim().toLowerCase() == 'open shift'
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
        _safeSetState(() {
          isCheckedIn = data['current_status'] == 'checked_in';
          isAllowedToCheckIn = !isCheckedIn;
          isAllowedToCheckOut = isCheckedIn;
          isShiftSelectable = true;
          // Only set shift from status API when checked in; when not checked in,
          // preserve whatever fetchShifts already selected
          if (isCheckedIn) selectedShift = shiftId;
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
        debugPrint(
          'Updated state - isCheckedIn: $isCheckedIn, isAllowedToCheckIn: $isAllowedToCheckIn, isAllowedToCheckOut: $isAllowedToCheckOut, selectedShift: $selectedShift, empShifts: ${empShifts.length}',
        );
      } else {
        // Any non-success response â€” fail silently, user stays logged in
        debugPrint('fetchStatus failed silently: ${data['message']}');
      }
    } catch (e) {
      debugPrint('fetchStatus exception: $e');
    } finally {
      _safeSetState(() => isStatusLoading = false);
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
          const SnackBar(
            content: Text('Check-in cancelled.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _showNotification(
        title: 'Cancelled',
        body: 'Check-in cancelled by you.',
      );
      return;
    }

    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => AlertDialog(
                title: const Text('Location Required'),
                content: const Text(
                  'Please enable location services to check in.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
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
      await _showNotification(
        title: 'Location Off',
        body: 'Enable location to check in.',
      );
      return;
    }

    try {
      _safeSetState(() {
        isProcessingCheckIn = true;
        isProcessing = true;
      });

      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final position = await _getCurrentLocation();

      // â”€â”€ Late check-in detection (hospital/VHS accounts only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (_isVHS) {
        await _checkAndHandleLateCheckIn();
        if (!mounted) return;
      }
      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
      debugPrint('CheckIn Response: $data');

      if (response.statusCode == 200 && data['status'] == 'success') {
        // Update UI & state
        await fetchStatus();
        final cumTimeStr = data['cumulative_working_hours'] ?? '00:00:00';
        workingDuration = _parseDuration(cumTimeStr);
        sessionStart = DateTime.now();
        checkInTime = DateFormat('hh:mm:ss a').format(sessionStart!);
        _safeSetState(
          () => totalWorkingHours = _formatDuration(workingDuration),
        );

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

        // Show outside boundary warning if applicable
        final fenceDistance =
            double.tryParse(data['distance_from_fence']?.toString() ?? '') ??
            0.0;
        if (fenceDistance > 0) {
          _showOutsideBoundaryDialog(true);
        }

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
          body:
              '${data['message'] ?? 'Checked in at $checkInTime'} - Shift: $selectedShift',
        );

        // VERY IMPORTANT: Ask user to disable battery optimization
        if (!await Permission.ignoreBatteryOptimizations.isGranted) {
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder:
                  (ctx) => AlertDialog(
                    title: const Text("Important for Accurate Attendance"),
                    content: const Text(
                      "To make sure your attendance is recorded even when the app is closed:\n\n"
                      "â†’ Go to Settings â†’ Apps â†’ This App â†’ Battery â†’ Choose 'Unrestricted' or 'No restrictions'\n\n"
                      "Without this, Android may stop tracking when app is closed.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          await Permission.ignoreBatteryOptimizations.request();
                          if (ctx.mounted) Navigator.pop(ctx);
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
      } else if (_isAuthError(data['message'])) {
        await _showInvalidTokenDialog();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Check-In Failed'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        _handleError(
          'Check-In Failed',
          Exception(data['message'] ?? 'Unknown error'),
        );
        await _showNotification(
          title: 'Check-In Failed',
          body: data['message'] ?? 'Try again later.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-In Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _handleError('Check-In Error', e);
      await _showNotification(title: 'Check-In Error', body: 'Error: $e');
    } finally {
      _safeSetState(() {
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
      await _showNotification(
        title: 'In Progress',
        body: 'Checkout already running. Wait.',
      );
      return;
    }

    if (selectedShift == null) {
      _handleError('No shift', Exception('No shift selected'));
      await _showNotification(
        title: 'No Shift',
        body: 'Select shift before checkout.',
      );
      return;
    }

    bool confirmed = await _showConfirmationDialog(
      context,
      'Are you sure you want to check out?',
    );
    if (!confirmed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check-out cancelled.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _showNotification(
        title: 'Cancelled',
        body: 'Check-out cancelled by you.',
      );
      return;
    }

    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => AlertDialog(
                title: const Text('Location Required'),
                content: const Text(
                  'Please enable location services to check out.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
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
      await _showNotification(
        title: 'Location Off',
        body: 'Enable location to check out.',
      );
      return;
    }

    _safeSetState(() {
      isProcessingCheckOut = true;
      isProcessing = true;
    });

    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
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
      debugPrint('CheckOut Response: $data');

      if (response.statusCode == 200 && data['status'] == 'success') {
        await fetchStatus();
        stopWorkingTimer();
        _stopLocationSending();

        final nowLocal = DateTime.now();
        checkOutTime = DateFormat('hh:mm:ss a').format(nowLocal);
        final cumTimeStr = data['cumulative_working_hours'] ?? '00:00:00';
        workingDuration = _parseDuration(cumTimeStr);

        _safeSetState(
          () => totalWorkingHours = _formatDuration(workingDuration),
        );

        await _saveState();

        // Stop Workmanager
        await Workmanager().cancelByUniqueName(finalLocationTask);
        debugPrint('Workmanager task cancelled on check-out');

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // STOP FOREGROUND SERVICE CORRECTLY (no await needed)
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        final service = FlutterBackgroundService();
        service.invoke('stop'); // â† No await here
        debugPrint('Foreground service stop requested');

        // Update background state
        FlutterBackgroundService().invoke('updateState', {
          'isCheckedIn': isCheckedIn,
          'empId': widget.empId,
          'authToken': widget.authToken,
          'deviceSerialNumber': widget.deviceSerialNumber,
          'selectedShift': selectedShift,
        });

        // Show outside boundary warning if applicable
        final fenceDistance =
            double.tryParse(data['distance_from_fence']?.toString() ?? '') ??
            0.0;
        if (fenceDistance > 0) {
          _showOutsideBoundaryDialog(false);
        }

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
          body:
              '${data['message'] ?? 'Checked out at $checkOutTime'}. Total: $totalWorkingHours',
        );

        // Do not clear SharedPreferences or navigate to Login Screen on successful checkout,
        // so that the user remains logged in.
      } else if (_isAuthError(data['message'])) {
        await _showInvalidTokenDialog();
      } else {
        await fetchStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Check-Out Failed'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        _handleError(
          'Check-Out Failed',
          Exception(data['message'] ?? 'Unknown'),
        );
        await _showNotification(
          title: 'Check-Out Failed',
          body: data['message'] ?? 'Try again.',
        );
      }
    } catch (e) {
      await fetchStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-Out Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _handleError('Check-Out Error', e);
      await _showNotification(title: 'Check-Out Error', body: 'Error: $e');
    } finally {
      _safeSetState(() {
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

  void _showOutsideBoundaryDialog(bool isCheckIn) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text(
                  "Outside Boundary",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              "You are outside the approved location boundary. Your ${isCheckIn ? 'check-in' : 'check-out'} has been recorded successfully, but is flagged as outside the premises.",
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "OK",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _showInvalidTokenDialog() async {
    if (!mounted || _isSessionDialogShowing) return;
    _isSessionDialogShowing = true;
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
                  // Preserve login credentials so silent re-login works next time
                  final savedUserId = prefs.getString('savedUserId') ?? '';
                  final savedPassword = prefs.getString('savedPassword') ?? '';
                  final savedDeviceSerial =
                      prefs.getString('deviceSerialNumber') ?? '';
                  final savedFcm = prefs.getString('fcm_token') ?? '';
                  await prefs.clear();
                  if (savedUserId.isNotEmpty)
                    await prefs.setString('savedUserId', savedUserId);
                  if (savedPassword.isNotEmpty)
                    await prefs.setString('savedPassword', savedPassword);
                  if (savedDeviceSerial.isNotEmpty)
                    await prefs.setString(
                      'deviceSerialNumber',
                      savedDeviceSerial,
                    );
                  if (savedFcm.isNotEmpty)
                    await prefs.setString('fcm_token', savedFcm);
                  debugPrint(
                    'Session reset â€” credentials preserved for silent login',
                  );
                  _isSessionDialogShowing = false;
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
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
      _safeSetState(() {
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
        builder:
            (ctx) => AlertDialog(
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

  /// Shows a late check-in reason dialog if the employee is checking in more
  /// than 15 minutes after their selected shift's start time, then silently
  /// submits an OT/Late request so the manager can approve/reject it.
  Future<void> _checkAndHandleLateCheckIn() async {
    if (selectedShift == null) return;

    final shiftData = empShifts.firstWhere(
      (s) => s['id'] == selectedShift,
      orElse: () => <String, dynamic>{},
    );
    final DateTime? shiftStart = shiftData['startTime'] as DateTime?;
    if (shiftStart == null) return;

    final now = DateTime.now();
    final lateBy = now.difference(shiftStart);
    if (lateBy.inMinutes <= 15) return; // on time â€“ nothing to do

    if (!mounted) return;
    final reasonController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Icon(Icons.schedule_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Late Check-In',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are checking in ${lateBy.inMinutes} minute(s) late. '
                  'Please provide a reason for manager approval.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Reason for late check-in...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Submit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (submitted == true && reasonController.text.trim().isNotEmpty) {
      try {
        await ApiService.submitOtRequest(
          empId: widget.empId,
          authToken: widget.authToken,
          requestType: 'late_checkin',
          date: DateFormat('yyyy-MM-dd').format(now),
          reason: reasonController.text.trim(),
          duration:
              '${lateBy.inHours.toString().padLeft(2, '0')}:${(lateBy.inMinutes % 60).toString().padLeft(2, '0')}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Late check-in request submitted for manager approval.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (_) {}
    }
    reasonController.dispose();
  }

  Widget _quickCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.3,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: color.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
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
          _safeSetState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items:
            _isVHS
                // VHS: 4 tabs — no Tasks
                ? [
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/attndance_logo.png'),
                      size: 24,
                      color:
                          _selectedIndex == 0
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Attendance',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/leave_logo.png'),
                      size: 24,
                      color:
                          _selectedIndex == 1
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Leaves',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/approval_logos.png'),
                      size: 24,
                      color:
                          _selectedIndex == 2
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Expenses',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/up_more.png'),
                      size: 24,
                      color:
                          _selectedIndex == 3
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'More',
                  ),
                ]
                // Eltrive & others: 5 tabs
                : [
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/attndance_logo.png'),
                      size: 24,
                      color:
                          _selectedIndex == 0
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Attendance',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/leave_logo.png'),
                      size: 24,
                      color:
                          _selectedIndex == 1
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Leaves',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/payslip_icon.png'),
                      size: 24,
                      color:
                          _selectedIndex == 2
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Tasks',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/approval_logos.png'),
                      size: 24,
                      color:
                          _selectedIndex == 3
                              ? Colors.greenAccent
                              : Colors.black54,
                    ),
                    label: 'Expenses',
                  ),
                  BottomNavigationBarItem(
                    icon: ImageIcon(
                      AssetImage('assets/up_more.png'),
                      size: 24,
                      color:
                          _selectedIndex == 4
                              ? Colors.greenAccent
                              : Colors.black54,
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
        debugPrint(
          'Button State: isAllowedToCheckIn=$isAllowedToCheckIn, isAllowedToCheckOut=$isAllowedToCheckOut, selectedShift=$selectedShift, isProcessing=$isProcessing, activeShift=${empShifts.any((shift) => shift['id'] == selectedShift && shift['isActive'] as bool)}',
        );
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Fixed header — stays visible while body scrolls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  height: 68,
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
                                    builder:
                                        (_) => AdminPage(
                                          empName: widget.empName,
                                          companyId: widget.companyId,
                                        ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      Center(child: _companyLogoWidget()),
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
                                  builder:
                                      (_) => EmpProfile(
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
              const SizedBox(height: 2),
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
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: widget.empName.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF0C0D0C),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                today,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Divider(
                height: 8,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
              ),
              // ── Scrollable body ────────────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _lastAutoRefresh = DateTime.now();
                    await fetchShifts();
                    await fetchStatus();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 6,
                          ),
                          child:
                              isShiftsLoading || isStatusLoading
                                  ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                  // ── Single shift → show as a locked info card ──────────────
                                  : empShifts.length == 1
                                  ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.teal.shade100,
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.badge_rounded,
                                          color: Colors.teal.shade700,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Assigned Shift',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.teal.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                empShifts[0]['name']
                                                        ?.toString() ??
                                                    '',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.lock_outline_rounded,
                                          color: Colors.teal.shade300,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  )
                                  // ── Multiple shifts → show dropdown ────────────────────────
                                  : empShifts.isEmpty
                                  ? Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.orange.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            'No shifts assigned. Contact your admin.',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  : DropdownButtonFormField<String>(
                                    initialValue: selectedShift,
                                    isExpanded: true,
                                    hint: const Text(
                                      'Select Your Shift',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    dropdownColor: Colors.white,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                      labelText: 'Select Shift',
                                      labelStyle: TextStyle(
                                        color: Colors.teal.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.badge_rounded,
                                        color: Colors.teal.shade700,
                                        size: 22,
                                      ),
                                      filled: true,
                                      fillColor: Colors.teal.shade50.withValues(
                                        alpha: 0.3,
                                      ),
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
                                    icon: Icon(
                                      Icons.arrow_drop_down_rounded,
                                      color: Colors.teal.shade700,
                                      size: 28,
                                    ),
                                    items:
                                        empShifts.map((shift) {
                                          return DropdownMenuItem<String>(
                                            value: shift['id'],
                                            child: Text(
                                              shift['name']?.toString() ?? '',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                    onChanged:
                                        isShiftSelectable
                                            ? (value) async {
                                              if (value != null) {
                                                final selectedShiftName =
                                                    empShifts.firstWhere(
                                                      (shift) =>
                                                          shift['id'] == value,
                                                      orElse:
                                                          () => {
                                                            'name': 'Unknown',
                                                          },
                                                    )['name'];
                                                bool confirmed =
                                                    await _showConfirmationDialog(
                                                      context,
                                                      'Are you sure you want to select the shift: $selectedShiftName?',
                                                    );
                                                if (confirmed) {
                                                  _safeSetState(() {
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
                                            orElse:
                                                () => {'name': 'General Shift'},
                                          )['name']
                                          : 'Shift selection unavailable',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                        ),
                        const SizedBox(height: 8),
                        // Total working hours — shown above buttons
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Shifts Working Time: $totalWorkingHours',
                            style: const TextStyle(
                              color: Color(0xFF121111),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
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
                                                    shift['id'] ==
                                                        selectedShift &&
                                                    shift['isActive'] as bool,
                                              ))
                                          ? () async {
                                            final selectedShiftData = empShifts
                                                .firstWhere(
                                                  (shift) =>
                                                      shift['id'] ==
                                                      selectedShift,
                                                  orElse:
                                                      () => {'isActive': false},
                                                );
                                            if (selectedShiftData['isActive']
                                                as bool) {
                                              await handleCheckIn();
                                            } else {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Please select an active shift.',
                                                  ),
                                                  duration: Duration(
                                                    seconds: 2,
                                                  ),
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
                                                      shift['id'] ==
                                                          selectedShift &&
                                                      shift['isActive'] as bool,
                                                ))
                                            ? 1.0
                                            : 0.4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
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
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Icon(
                                            Icons.login,
                                            size: 28,
                                            color: Colors.black,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            checkInTime,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Text(
                                            'Check In',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 12,
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
                                        (isAllowedToCheckOut && !isProcessing)
                                            ? 1.0
                                            : 0.4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
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
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Icon(
                                            Icons.logout,
                                            size: 28,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            checkOutTime,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Text(
                                            'Check Out',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
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
                        const SizedBox(height: 10),
                        // Attendance calendar
                        _buildAttendanceCalendar(),
                        const SizedBox(height: 20),
                        // â”€â”€ Quick-access cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        // Attendance History: all companies
                        // OT / Late Request:  hospital / VHS accounts only
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: _quickCard(
                                  icon: Icons.history_rounded,
                                  label: 'Attendance\nHistory',
                                  color: Colors.teal,
                                  onTap:
                                      () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => AttendanceHistoryScreen(
                                                empId: widget.empId,
                                                authToken: widget.authToken,
                                                empName: widget.empName,
                                              ),
                                        ),
                                      ),
                                ),
                              ),
                              if (_isVHS) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _quickCard(
                                    icon: Icons.more_time_rounded,
                                    label: 'OT / Late\nRequest',
                                    color: Colors.deepOrange,
                                    onTap:
                                        () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => OtLateRequestScreen(
                                                  empId: widget.empId,
                                                  authToken: widget.authToken,
                                                  empName: widget.empName,
                                                ),
                                          ),
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      // VHS (company 2): 4 tabs — Attendance / Leaves / Expenses / More
      if (_isVHS) {
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
            return VHSExpensesScreen(
              empId: widget.empId,
              empName: widget.empName,
              authToken: widget.authToken,
              companyId: widget.companyId,
              deviceSerialNumber: widget.deviceSerialNumber,
              isAdmin: isAdminUser,
            );
          case 3:
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

      // Eltrive & others: 5 tabs
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
