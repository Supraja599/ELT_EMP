import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';

import 'login_screen.dart';
import 'services/api_service.dart';
import 'check_in_out_screen.dart';

/// ---------------------------------------------------------------------------
///  ADMIN PAGE – now with tabbed filtering (Check-In / Check-Out / Device / Leave)
/// ---------------------------------------------------------------------------
class AdminPage extends StatefulWidget {
  final String empName;

  // Existing lists
  final List<Map<String, dynamic>> pendingCheckinRequests;
  final List<Map<String, dynamic>> pendingCheckoutRequests;
  final List<Map<String, dynamic>> pendingDeviceRequests;

  // NEW – leave requests (same shape as the others, just add a "type":"leave")
  final List<Map<String, dynamic>> pendingLeaveRequests;

  const AdminPage({
    super.key,
    required this.empName,
    this.pendingCheckinRequests = const [],
    this.pendingCheckoutRequests = const [],
    this.pendingDeviceRequests = const [],
    this.pendingLeaveRequests = const [],
  });

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // -----------------------------------------------------------------------
  // 1. NEW – mutable copies of the incoming lists
  // -----------------------------------------------------------------------
  late List<Map<String, dynamic>> _checkin;
  late List<Map<String, dynamic>> _checkout;
  late List<Map<String, dynamic>> _device;
  late List<Map<String, dynamic>> _leave;

  late TabController _tabController;
  int _selectedTabIndex = 0; // 0=checkin, 1=checkout, 2=device, 3=leave

  // Each tab works on its own list + a carousel index
  late List<Map<String, dynamic>> _filteredRequests;
  int _carouselIndex = 0;

  // Loading flag (shared for all tabs)
  bool isLoading = false;
  DateTime? _lastConnectivityCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // --------------------------------------------------------------
    // Initialise mutable copies (deep-copy so we don’t mutate props)
    // --------------------------------------------------------------
    _checkin = widget.pendingCheckinRequests.map((e) => Map<String, dynamic>.from(e)).toList();
    _checkout = widget.pendingCheckoutRequests.map((e) => Map<String, dynamic>.from(e)).toList();
    _device = widget.pendingDeviceRequests.map((e) => Map<String, dynamic>.from(e)).toList();
    _leave = widget.pendingLeaveRequests.map((e) => Map<String, dynamic>.from(e)).toList();

    // Initialise tab controller (4 tabs)
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _selectedTabIndex = _tabController.index;
        _carouselIndex = 0; // reset carousel when switching tabs
        _updateFilteredList();
      });
    });

    // Start with the first tab
    _updateFilteredList();
    debugPrint(
        'AdminPage init – total check-in:${_checkin.length} '
            'check-out:${_checkout.length} '
            'device:${_device.length} '
            'leave:${_leave.length}');

    // Auto-fetch latest requests from server on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPendingRequests();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('Admin page resumed. Auto-refreshing pending requests...');
      _refreshPendingRequests();
    }
  }

  // -----------------------------------------------------------------------
  // 2. Updated filtered-list builder – now reads from the mutable copies
  // -----------------------------------------------------------------------
  void _updateFilteredList() {
    switch (_selectedTabIndex) {
      case 0:
        _filteredRequests = _checkin
            .map((e) => {...e, "type": "checkin"})
            .toList();
        break;
      case 1:
        _filteredRequests = _checkout
            .map((e) => {...e, "type": "checkout"})
            .toList();
        break;
      case 2:
        _filteredRequests = _device
            .map((e) => {...e, "type": "device"})
            .toList();
        break;
      case 3:
        _filteredRequests = _leave
            .map((e) => {...e, "type": "leave"})
            .toList();
        break;
    }

    // Clamp carousel index after a change
    if (_filteredRequests.isEmpty) {
      _carouselIndex = 0;
    } else if (_carouselIndex >= _filteredRequests.length) {
      _carouselIndex = _filteredRequests.length - 1;
    }
  }

  // -----------------------------------------------------------------------
  // 3. Connectivity helper (unchanged)
  // -----------------------------------------------------------------------
  Future<bool> _checkConnectivity({bool useDialog = false}) async {
    // debounce …
    if (_lastConnectivityCheck != null &&
        DateTime.now().difference(_lastConnectivityCheck!).inSeconds < 5) {
      return true;
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      if (mounted) {
        if (useDialog) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("No Internet"),
              content: const Text(
                  "No internet connection. Please check and try again."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "No internet connection. Please check and try again."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      return false;
    }

    // actual reachability test
    try {
      final response = await ApiService.pingGoogle();
      if (response.statusCode == 200) {
        _lastConnectivityCheck = DateTime.now();
        return true;
      }
    } catch (e) {
      debugPrint('Internet check failed: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No internet access. Please check your connection."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // 4. API – approve / reject (updated to remove from source)
  // -----------------------------------------------------------------------
  Future<void> _updateRequestStatus(
      String requestId, String status, String type, String requestName) async {
    if (!await _checkConnectivity(useDialog: true)) return;
    setState(() => isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("authToken") ?? "";
    if (token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Session expired. Please log in again."),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }
      return;
    }

    int? parsedId;
    try {
      parsedId = int.parse(requestId);
    } catch (e) {
      debugPrint('Invalid requestId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid request ID format."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() => isLoading = false);
      return;
    }

    Uri url;
    Map<String, dynamic> body;

    // -------------------------------------------------------------------
    // Build URL / body per type (added a tiny branch for leave)
    // -------------------------------------------------------------------
    if (type == 'checkin') {
      url = Uri.parse(
          "https://hrm.eltrive.com/api/shift-requests/update/$requestId");
      body = {"auth_token": token, "status": status};
    } else if (type == 'checkout') {
      url = Uri.parse(
          "https://hrm.eltrive.com/api/checkoutrequests/updateRequestStatus/$requestId");
      final checkoutTime = status == 'approved'
          ? (_filteredRequests[_carouselIndex]['request_time'] ??
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()))
          : null;
      body = {
        "auth_token": token,
        "status": status,
        "checkout_time":
        checkoutTime ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      };
    } else if (type == 'device') {
      url = status == 'approved'
          ? Uri.parse(
          "https://hrm.eltrive.com/api/device-requests/approve/$parsedId")
          : Uri.parse(
          "https://hrm.eltrive.com/api/device-requests/reject/$parsedId");
      body = {"auth_token": token};
    } else if (type == 'leave') {
      url = Uri.parse(
          "https://hrm.eltrive.com/api/leave-requests/${status == 'approved' ? 'approve' : 'reject'}/$parsedId");
      body = {"auth_token": token};
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Unknown request type: $type"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() => isLoading = false);
      return;
    }

    // -------------------------------------------------------------------
    // Send request
    // -------------------------------------------------------------------
    try {
      debugPrint('POST $url  body:${jsonEncode(body)}');
      final response = await ApiService.updateRequestStatus(
        url: url.toString(),
        authToken: token,
        body: body,
      );

      final data = jsonDecode(response.body);
      debugPrint(
          'Response ${response.statusCode} – ${data['status'] ?? 'no status'}');

      if (response.statusCode == 200 && data['status'] == 'success') {
        // -----------------------------------------------------------
        // SUCCESS – remove from source list and refresh filtered
        // -----------------------------------------------------------
        switch (type) {
          case 'checkin':
            _checkin.removeWhere((e) => e['id'].toString() == requestId);
            break;
          case 'checkout':
            _checkout.removeWhere((e) => e['id'].toString() == requestId);
            break;
          case 'device':
            _device.removeWhere((e) => e['id'].toString() == requestId);
            break;
          case 'leave':
            _leave.removeWhere((e) => e['id'].toString() == requestId);
            break;
        }

        // Refresh UI
        setState(() {
          _updateFilteredList();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "${type.capitalize()} request '$requestName' ${status.capitalize()} successfully"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        final msg = data['message'] ?? 'Server error';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed: $msg"),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  // -----------------------------------------------------------------------
  // 5. Refresh pending requests
  // -----------------------------------------------------------------------
  Future<void> _refreshPendingRequests() async {
    if (!await _checkConnectivity(useDialog: true)) return;
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("authToken") ?? "";
      final response = await ApiService.fetchPendingRequests(
        authToken: token,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'success') {
          _checkin = (json['pending_checkin_requests'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _checkout = (json['pending_checkout_requests'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _device = (json['pending_device_requests'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _leave = (json['pending_leave_requests'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          setState(() {
            _updateFilteredList();
          });

          // Update SharedPreferences
          await prefs.setString("pendingCheckinRequests", jsonEncode(_checkin));
          await prefs.setString("pendingCheckoutRequests", jsonEncode(_checkout));
          await prefs.setString("pendingDeviceRequests", jsonEncode(_device));
          await prefs.setString("pendingLeaveRequests", jsonEncode(_leave));
        }
      }
    } catch (e) {
      debugPrint("Refresh error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to refresh requests."),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  // -----------------------------------------------------------------------
  // 6. Confirmation dialog (unchanged)
  // -----------------------------------------------------------------------
  Future<void> _showConfirmDialog(
      BuildContext context,
      String requestId,
      String action,
      String type,
      String requestName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("${action.capitalize()} ${type.capitalize()} Request"),
        content:
        Text("Are you sure you want to $action the $type request for '$requestName'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Yes", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateRequestStatus(requestId, action, type, requestName);
    }
  }

  // -----------------------------------------------------------------------
  // 7. UI – Scaffold with TabBar + carousel per tab
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final current = _filteredRequests.isNotEmpty ? _filteredRequests[_carouselIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.login), text: "Check-In"),
            Tab(icon: Icon(Icons.logout), text: "Check-Out"),
            Tab(icon: Icon(Icons.devices), text: "Device"),
            Tab(icon: Icon(Icons.event_available), text: "Leave"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_pin_circle_rounded, color: Colors.white),
            tooltip: "Switch to Attendance View",
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final deviceSerial = prefs.getString('deviceSerialNumber') ?? 'unknown_device_id';
              final companyId = prefs.getString('companyId') ?? '';
              final empId = prefs.getString('empId') ?? '0';
              final token = prefs.getString('authToken') ?? '';
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckInOutScreen(
                      empName: widget.empName,
                      empId: empId,
                      authToken: token,
                      deviceSerialNumber: deviceSerial,
                      companyId: companyId,
                      isAdmin: true,
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshPendingRequests,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator()
              : _filteredRequests.isEmpty
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text(
                "All requests handled for this tab!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          )
              : AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Card(
              key: ValueKey(current?['id']),
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ----- Header -----
                    Text(
                      "Request ${_carouselIndex + 1}/${_filteredRequests.length}",
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      current?['type'] == 'device'
                          ? 'Device Request – ${current?['first_name'] ?? ''} ${current?['last_name'] ?? ''}'
                          : current?['type'] == 'leave'
                          ? 'Leave Request – ${current?['first_name'] ?? ''} ${current?['last_name'] ?? ''}'
                          : current?['shift_name'] ?? 'Unknown Shift',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Employee: ${current?['first_name'] ?? ''} ${current?['last_name'] ?? ''}",
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Type: ${current?['type'].toString().capitalize()}",
                      style: const TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),

                    // ----- Type-specific fields -----
                    if (current?['type'] == 'device') ...[
                      Text(
                        "Old Device: ${current?['old_device_serial'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "New Device: ${current?['new_device_serial'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Requested: ${current?['requested_at'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    ] else if (current?['type'] == 'leave') ...[
                      Text(
                        "Leave Type: ${current?['leave_type'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "From: ${current?['start_date'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "To: ${current?['end_date'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    ] else ...[
                      // check-in / check-out
                      Text(
                        "Shift Time: ${current?['shift_time'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Request Time: ${current?['request_time'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 25),

                    // ----- Action buttons -----
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _showConfirmDialog(
                            context,
                            current?['id'].toString() ?? '',
                            "approved",
                            current?['type'] ?? '',
                            _displayName(current),
                          ),
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text("Approve",
                              style: TextStyle(color: Colors.white)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _showConfirmDialog(
                            context,
                            current?['id'].toString() ?? '',
                            "rejected",
                            current?['type'] ?? '',
                            _displayName(current),
                          ),
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text("Reject",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),

                    // ----- Navigation between requests in the same tab -----
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: _carouselIndex > 0
                              ? () => setState(() => _carouselIndex--)
                              : null,
                        ),
                        Text(
                            "${_carouselIndex + 1} / ${_filteredRequests.length}"),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: _carouselIndex <
                              _filteredRequests.length - 1
                              ? () => setState(() => _carouselIndex++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper to build a readable name for the confirmation dialog
  String _displayName(Map<String, dynamic>? req) {
    if (req == null) return '';
    final type = req['type'] as String?;
    switch (type) {
      case 'device':
        return 'Device for ${req['first_name']} ${req['last_name']}';
      case 'leave':
        return 'Leave for ${req['first_name']} ${req['last_name']}';
      default:
        return req['shift_name'] ?? 'Shift Request';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Small utility extension (unchanged)
// ---------------------------------------------------------------------------
extension StringExtension on String {
  String capitalize() => isEmpty ? this : "${this[0].toUpperCase()}${substring(1)}";
}