import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://hrm.eltrive.com/api';
  static const String baseUrlAlt = 'https://hrm.eltrive.com/Api';

  /// Ping Google to check internet connectivity.
  static Future<http.Response> pingGoogle() {
    return http
        .get(Uri.parse('https://www.google.com'))
        .timeout(const Duration(seconds: 5));
  }

  /// 1. Login
  static Future<http.Response> login({
    required String userId,
    required String password,
    required String deviceId,
    required String latitude,
    required String longitude,
    required String fcmToken,
  }) {
    return http
        .post(
          Uri.parse('$baseUrl/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'password': password,
            'device_serial_number': deviceId,
            'latitude': latitude,
            'longitude': longitude,
            'fcm_token': fcmToken,
          }),
        )
        .timeout(const Duration(seconds: 12));
  }

  /// Helpers for automatic session recovery / silent re-login

  static bool _isInvalidTokenResponse(http.Response response) {
    try {
      if (response.body.isNotEmpty) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('message')) {
          final msg = data['message']?.toString().toLowerCase() ?? '';
          if (msg.contains('invalid token') ||
              msg.contains('token invalid') ||
              msg.contains('session expired') ||
              msg.contains('expired token') ||
              msg.contains('employee not found') ||
              msg.contains('code mismatch')) {
            return true;
          }
        }
      }
    } catch (_) {}
    if (response.statusCode == 401) {
      return true;
    }
    return false;
  }

  static Future<String> _getBestToken(String passedToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('authToken') ?? '';
      if (savedToken.isNotEmpty && savedToken != passedToken) {
        return savedToken;
      }
    } catch (_) {}
    return passedToken;
  }

  static Future<String?> attemptSilentLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('savedUserId') ?? '';
      final password = prefs.getString('savedPassword') ?? '';
      final deviceId = prefs.getString('deviceSerialNumber') ?? '';
      final fcmToken = prefs.getString('fcm_token') ?? '';

      if (userId.isEmpty || password.isEmpty || deviceId.isEmpty) {
        return null;
      }

      final response = await login(
        userId: userId,
        password: password,
        deviceId: deviceId,
        latitude: '0.0',
        longitude: '0.0',
        fcmToken: fcmToken,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'success') {
          final authToken = json['auth_token'] ?? '';
          final companyId = json['company_id']?.toString() ?? '';
          final companyLogo = json['company_logo']?.toString() ?? '';
          final role =
              json['user_role']?.toString() ??
              (json['emp_id']?.toString() == '0' ? 'admin' : 'employee');
          final empName = json['emp_name'] ?? 'Employee';
          final empId = json['emp_id']?.toString() ?? '';

          await prefs.setString('authToken', authToken);
          await prefs.setString('companyId', companyId);
          await prefs.setString('companyLogo', companyLogo);
          await prefs.setString('userRole', role);
          await prefs.setString('empName', empName);
          await prefs.setString('empId', empId);

          return authToken;
        }
      }
    } catch (e) {
      debugPrint('Silent login failed: $e');
    }
    return null;
  }

  static Future<http.Response> _postWithAutoRetry({
    required String url,
    required String authToken,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    Duration timeoutDuration = const Duration(seconds: 10),
  }) async {
    final activeToken = await _getBestToken(authToken);

    final Map<String, String> activeHeaders =
        headers != null
            ? Map<String, String>.from(headers)
            : {'Content-Type': 'application/json'};
    if (activeHeaders.containsKey('Authorization')) {
      activeHeaders['Authorization'] = 'Bearer $activeToken';
    }

    final Map<String, dynamic> activeBody = Map<String, dynamic>.from(body);
    if (activeBody.containsKey('auth_token')) {
      activeBody['auth_token'] = activeToken;
    }
    if (activeBody.containsKey('authToken')) {
      activeBody['authToken'] = activeToken;
    }

    http.Response response = await http
        .post(
          Uri.parse(url),
          headers: activeHeaders,
          body: jsonEncode(activeBody),
        )
        .timeout(timeoutDuration);

    if (_isInvalidTokenResponse(response)) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        if (activeHeaders.containsKey('Authorization')) {
          activeHeaders['Authorization'] = 'Bearer $newToken';
        }
        if (activeBody.containsKey('auth_token')) {
          activeBody['auth_token'] = newToken;
        }
        if (activeBody.containsKey('authToken')) {
          activeBody['authToken'] = newToken;
        }
        response = await http
            .post(
              Uri.parse(url),
              headers: activeHeaders,
              body: jsonEncode(activeBody),
            )
            .timeout(timeoutDuration);
      }
    }
    return response;
  }

  static Future<http.Response> _getWithAutoRetry({
    required String url,
    required String authToken,
    Duration timeoutDuration = const Duration(seconds: 10),
  }) async {
    final activeToken = await _getBestToken(authToken);

    http.Response response = await http
        .get(Uri.parse(url), headers: {'Authorization': 'Bearer $activeToken'})
        .timeout(timeoutDuration);

    if (_isInvalidTokenResponse(response)) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        response = await http
            .get(Uri.parse(url), headers: {'Authorization': 'Bearer $newToken'})
            .timeout(timeoutDuration);
      }
    }
    return response;
  }

  /// 2. Save FCM Token
  static Future<http.Response> saveFcmToken({
    required String fcmToken,
    required String authToken,
    required String empId,
    required String companyId,
    String? deviceSerial,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/save-fcm-token',
      authToken: authToken,
      body: {
        'fcm_token': fcmToken,
        'auth_token': authToken,
        'emp_id': empId,
        'company_id': companyId,
        if (deviceSerial != null) 'device_serial_number': deviceSerial,
      },
      timeoutDuration: const Duration(seconds: 8),
    );
  }

  /// 3. Update FCM Token (during token refresh)
  static Future<http.Response> updateFcmToken({
    required String token,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/update_fcm_token',
      authToken: authToken,
      body: {'auth_token': authToken, 'fcm_token': token},
    );
  }

  /// 4. Apply Leave
  static Future<http.Response> applyLeave({
    required String authToken,
    required String empId,
    required String leaveTypeId,
    required String fromDate,
    required String toDate,
    required String reason,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/leaveapply',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'emp_id': empId,
        'leave_type_id': leaveTypeId,
        'from_date': fromDate,
        'to_date': toDate,
        'reason': reason,
      },
    );
  }

  /// 5. Fetch Master Data (expense types, project types, fuel types, companies)
  /// POST /api/masterdata â€” Authorization: Bearer TOKEN (no body needed)
  static Future<http.Response> fetchMasterData({
    required String authToken,
  }) async {
    final token = await _getBestToken(authToken);
    return http
        .post(
          Uri.parse('$baseUrl/masterdata'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 12));
  }

  /// 6. Create Expense (normal or fuel)
  /// POST /api/expense â€” auth_token in body
  /// Normal body: {auth_token, expenses_type_id, project_type_id, gst_applicable,
  ///               company_id, details:[{bill_number, billnumber1, bill_date,
  ///               amount, bill_file_base64, bill_file_ext}]}
  /// Fuel body:   {auth_token, expenses_type_id, project_type_id, gst_applicable,
  ///               fuel_type_id, details:[{bill_date, billnumber1, amount,
  ///               started_km, ended_km, authorized_by, bill_file_base64, bill_file_ext}]}
  static Future<http.Response> createExpense({
    required String authToken,
    required Map<String, dynamic> body,
  }) async {
    final token = await _getBestToken(authToken);
    final payload = Map<String, dynamic>.from(body);
    payload['auth_token'] = token;

    return http
        .post(
          Uri.parse('$baseUrl/expense'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(minutes: 2));
  }

  /// 7. Fetch Employee Details
  static Future<http.Response> fetchEmployeeDetails({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/employee-details',
      authToken: authToken,
      body: {'emp_id': empId, 'auth_token': authToken},
    );
  }

  /// 8. Fetch Employee Photo
  static Future<http.Response> fetchEmployeePhoto({
    required String photoUrl,
    required String authToken,
  }) {
    return _getWithAutoRetry(url: photoUrl, authToken: authToken);
  }

  /// 9. Send Location Update (Location Tracker)
  static Future<http.Response> sendLocationUpdate(
    Map<String, dynamic> payload,
  ) async {
    final passedToken = payload['auth_token'] ?? '';
    final activeToken = await _getBestToken(passedToken);

    final Map<String, dynamic> activePayload = Map<String, dynamic>.from(
      payload,
    );
    activePayload['auth_token'] = activeToken;

    http.Response response = await http.post(
      Uri.parse('$baseUrl/locationtracker'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(activePayload),
    );

    if (_isInvalidTokenResponse(response)) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        activePayload['auth_token'] = newToken;
        response = await http.post(
          Uri.parse('$baseUrl/locationtracker'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(activePayload),
        );
      }
    }
    return response;
  }

  /// 10. Fetch Shifts
  static Future<http.Response> fetchShifts({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/shifts',
      authToken: authToken,
      body: {'emp_code': empId, 'auth_token': authToken},
    );
  }

  /// 11. Fetch Status
  static Future<http.Response> fetchStatus({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrlAlt/status',
      authToken: authToken,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: {'emp_id': empId, 'auth_token': authToken},
    );
  }

  /// 12. Check In
  static Future<http.Response> checkIn({
    required String authToken,
    required String empId,
    required String shiftId,
    required String latitude,
    required String longitude,
    required String timestamp,
    required String deviceSerialNumber,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/checkin',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'emp_id': empId,
        'shift_id': shiftId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
        'device_serial_number': deviceSerialNumber,
      },
    );
  }

  /// 13. Check Out
  static Future<http.Response> checkOut({
    required String authToken,
    required String empId,
    required String shiftId,
    required String latitude,
    required String longitude,
    required String timestamp,
    required String deviceSerialNumber,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrlAlt/checkout',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'emp_id': empId,
        'shift_id': shiftId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
        'device_serial_number': deviceSerialNumber,
      },
    );
  }

  /// 14. Update Request Status (Admin)
  static Future<http.Response> updateRequestStatus({
    required String url,
    required String authToken,
    required Map<String, dynamic> body,
  }) {
    return _postWithAutoRetry(
      url: url,
      authToken: authToken,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: body,
    );
  }

  /// 15. Fetch Pending Requests (Admin)
  /// 15a. Fetch Attendance History
  /// POST /api/attendance â€” Authorization: Bearer TOKEN
  /// Body: {month: int, year: int}  (no emp_id, no auth_token in body)
  static Future<http.Response> fetchAttendanceHistory({
    required String authToken,
    required int month,
    required int year,
    String empId = '', // kept for signature compat, not sent
  }) async {
    final token = await _getBestToken(authToken);
    http.Response response = await http
        .post(
          Uri.parse('$baseUrl/attendance'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'month': month, 'year': year}),
        )
        .timeout(const Duration(seconds: 15));

    if (_isInvalidTokenResponse(response)) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        response = await http
            .post(
              Uri.parse('$baseUrl/attendance'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $newToken',
              },
              body: jsonEncode({'month': month, 'year': year}),
            )
            .timeout(const Duration(seconds: 15));
      }
    }
    return response;
  }

  /// 15b. Submit OT / Late / Early-Checkout Request
  static Future<http.Response> submitOtRequest({
    required String empId,
    required String authToken,
    required String
    requestType, // 'late_checkin' | 'early_checkout' | 'overtime'
    required String date,
    required String reason,
    required String duration,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/ot-request',
      authToken: authToken,
      body: {
        'emp_id': empId,
        'auth_token': authToken,
        'request_type': requestType,
        'date': date,
        'reason': reason,
        'duration': duration,
      },
    );
  }

  /// 15c. Fetch My OT / Late Requests (employee)
  static Future<http.Response> fetchOtRequests({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/ot-requests',
      authToken: authToken,
      body: {'emp_id': empId, 'auth_token': authToken},
    );
  }

  /// 15d. Admin: Fetch Pending OT Requests
  static Future<http.Response> fetchPendingOtRequests({
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/pending-ot-requests',
      authToken: authToken,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: {'auth_token': authToken},
    );
  }

  /// 15e. Admin: Approve or Reject an OT Request
  static Future<http.Response> approveOtRequest({
    required String authToken,
    required String requestId,
    required String action, // 'approve' | 'reject'
    String? remarks,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/ot-request-action',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'request_id': requestId,
        'action': action,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      },
    );
  }

  /// 15f. Fetch Leave Balance
  static Future<http.Response> fetchLeaveBalance({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/leave-balance',
      authToken: authToken,
      body: {'emp_id': empId, 'auth_token': authToken},
    );
  }

  /// 15g. Fetch Leave History
  static Future<http.Response> fetchLeaveHistory({
    required String empId,
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/leave-history',
      authToken: authToken,
      body: {'emp_id': empId, 'auth_token': authToken},
    );
  }

  /// 15h. Fetch Department Leave Quota (to warn when dept has too many on leave)
  static Future<http.Response> fetchDeptLeaveQuota({
    required String empId,
    required String authToken,
    required String fromDate,
    required String toDate,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/dept-leave-quota',
      authToken: authToken,
      body: {
        'emp_id': empId,
        'auth_token': authToken,
        'from_date': fromDate,
        'to_date': toDate,
      },
    );
  }

  static Future<http.Response> fetchPendingRequests({
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/pending-requests',
      authToken: authToken,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: {'auth_token': authToken},
      timeoutDuration: const Duration(seconds: 10),
    );
  }

  /// 16. Fetch Tasks
  static Future<http.Response> fetchTasks({required String authToken}) {
    return _getWithAutoRetry(url: '$baseUrl/tasks', authToken: authToken);
  }

  /// 17. Submit Task Report (Multipart)
  static Future<http.StreamedResponse> submitTaskReport({
    required String authToken,
    required String taskId,
    required String subproject,
    required String reportDate,
    required String reportTime,
    required String description,
    String? filePath,
  }) async {
    final activeToken = await _getBestToken(authToken);

    Future<http.StreamedResponse> sendRequest() async {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/taskreport'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $activeToken',
        'Accept': 'application/json',
      });

      request.fields['task_id'] = taskId;
      request.fields['subproject'] = subproject;
      request.fields['report_date'] = reportDate;
      request.fields['report_time'] = reportTime;
      request.fields['description'] = description;

      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }

      return request.send();
    }

    var response = await sendRequest();

    if (response.statusCode == 401) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/taskreport'),
        );

        request.headers.addAll({
          'Authorization': 'Bearer $newToken',
          'Accept': 'application/json',
        });

        request.fields['task_id'] = taskId;
        request.fields['subproject'] = subproject;
        request.fields['report_date'] = reportDate;
        request.fields['report_time'] = reportTime;
        request.fields['description'] = description;

        if (filePath != null) {
          request.files.add(
            await http.MultipartFile.fromPath('file', filePath),
          );
        }

        response = await request.send();
      }
    }

    return response;
  }

  /// 18. Submit Work Sheet Entry
  static Future<http.Response> applyPettyCash({
    required String authToken,
    required double amount,
    required String purpose,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/petty-cash/request',
      authToken: authToken,
      body: {'auth_token': authToken, 'requested_amount': amount, 'purpose': purpose},
    );
  }

  static Future<http.Response> fetchPettyCashHistory({
    required String authToken,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/petty-cash/list',
      authToken: authToken,
      body: {'auth_token': authToken},
    );
  }

  /// VHS Overtime: Create overtime request
  /// POST /api/overtime/create
  static Future<http.Response> createOvertimeVHS({
    required String authToken,
    required String empId,
    required String date,
    required String shiftId,
    required String checkinTime,
    required String checkoutTime,
    required int otMinutes,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/overtime/create',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'emp_id': empId,
        'date': date,
        'shift_id': shiftId,
        'checkin_time': checkinTime,
        'checkout_time': checkoutTime,
        'ot_minutes': otMinutes,
      },
    );
  }

  /// VHS Overtime: Fetch overtime history
  /// POST /api/overtime/list
  static Future<http.Response> fetchOvertimeListVHS({
    required String authToken,
    required String empId,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/overtime/list',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId},
    );
  }

  /// VHS Overtime Admin: Fetch all pending overtime records
  /// POST /api/adminrequests/pendingOvertime
  static Future<http.Response> fetchAdminOvertimeVHS({
    required String authToken,
    required String empId,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/adminrequests/pendingOvertime',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId},
    );
  }

  /// VHS Overtime Admin: Approve an overtime request
  /// POST /api/overtime/approve
  static Future<http.Response> approveOvertimeVHS({
    required String authToken,
    required String empId,
    required int id,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/overtime/approve',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId, 'id': id},
    );
  }

  /// VHS Overtime Admin: Reject an overtime request
  /// POST /api/overtime/reject
  static Future<http.Response> rejectOvertimeVHS({
    required String authToken,
    required String empId,
    required int id,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/overtime/reject',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId, 'id': id},
    );
  }

  /// Employee Regularization: Apply
  /// POST /api/regularization/apply
  static Future<http.Response> applyRegularization({
    required String authToken,
    required String empId,
    required String attendanceDate,
    required String requestedCheckin,
    required String requestedCheckout,
    required String reason,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/regularization/apply',
      authToken: authToken,
      body: {
        'auth_token': authToken,
        'emp_id': empId,
        'attendance_date': attendanceDate,
        'requested_checkin': requestedCheckin,
        'requested_checkout': requestedCheckout,
        'reason': reason,
      },
    );
  }

  /// Employee Regularization: Status / History
  /// POST /api/regularization/status
  static Future<http.Response> fetchRegularizationStatus({
    required String authToken,
    required String empId,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/regularization/status',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId},
    );
  }

  /// VHS Regularization Admin: Fetch all pending regularization records
  /// POST /api/adminrequests/pendingRegularizations
  static Future<http.Response> fetchAdminRegularizationVHS({
    required String authToken,
    required String empId,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/adminrequests/pendingRegularizations',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId},
    );
  }

  /// VHS Regularization Admin: Approve a regularization request
  /// POST /api/regularization/approve
  static Future<http.Response> approveRegularizationVHS({
    required String authToken,
    required String empId,
    required int id,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/regularization/approve',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId, 'id': id},
    );
  }

  /// VHS Regularization Admin: Reject a regularization request
  /// POST /api/regularization/reject
  static Future<http.Response> rejectRegularizationVHS({
    required String authToken,
    required String empId,
    required int id,
  }) {
    return _postWithAutoRetry(
      url: '$baseUrl/regularization/reject',
      authToken: authToken,
      body: {'auth_token': authToken, 'emp_id': empId, 'id': id},
    );
  }

  static Future<http.Response> submitWorkUpdate({
    required Map<String, dynamic> body,
  }) async {
    final passedToken = body['auth_token'] ?? '';
    final activeToken = await _getBestToken(passedToken);

    final Map<String, dynamic> activeBody = Map<String, dynamic>.from(body);
    activeBody['auth_token'] = activeToken;

    http.Response response = await http.post(
      Uri.parse('$baseUrl/sheet/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(activeBody),
    );

    if (_isInvalidTokenResponse(response)) {
      final newToken = await attemptSilentLogin();
      if (newToken != null) {
        activeBody['auth_token'] = newToken;
        response = await http.post(
          Uri.parse('$baseUrl/sheet/create'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(activeBody),
        );
      }
    }
    return response;
  }
}
