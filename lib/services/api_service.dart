import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://hrm.eltrive.com/api';
  static const String baseUrlAlt = 'https://hrm.eltrive.com/Api';

  /// Ping Google to check internet connectivity.
  static Future<http.Response> pingGoogle() {
    return http.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 5));
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
    return http.post(
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
    ).timeout(const Duration(seconds: 12));
  }

  /// 2. Save FCM Token
  static Future<http.Response> saveFcmToken({
    required String fcmToken,
    required String authToken,
    required String empId,
    required String companyId,
    String? deviceSerial,
  }) {
    return http.post(
      Uri.parse('$baseUrl/save-fcm-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fcm_token': fcmToken,
        'auth_token': authToken,
        'emp_id': empId,
        'company_id': companyId,
        if (deviceSerial != null) 'device_serial_number': deviceSerial,
      }),
    ).timeout(const Duration(seconds: 8));
  }

  /// 3. Update FCM Token (during token refresh)
  static Future<http.Response> updateFcmToken({
    required String token,
    required String authToken,
  }) {
    return http.post(
      Uri.parse('$baseUrl/update_fcm_token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'auth_token': authToken,
        'fcm_token': token,
      }),
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
    return http.post(
      Uri.parse('$baseUrl/leaveapply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'auth_token': authToken,
        'emp_id': empId,
        'leave_type_id': leaveTypeId,
        'from_date': fromDate,
        'to_date': toDate,
        'reason': reason,
      }),
    );
  }

  /// 5. Fetch Expenses
  static Future<http.Response> fetchExpenses() {
    return http.get(Uri.parse('$baseUrl/expenses'));
  }

  /// 6. Submit Expense
  static Future<http.Response> submitExpense({
    required double amount,
    required String description,
    required String date,
    String? receiptBase64,
  }) {
    return http.post(
      Uri.parse('$baseUrl/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': amount,
        'description': description,
        'date': date,
        if (receiptBase64 != null) 'receiptBase64': receiptBase64,
      }),
    ).timeout(const Duration(minutes: 1));
  }

  /// 7. Fetch Employee Details
  static Future<http.Response> fetchEmployeeDetails({
    required String empId,
    required String authToken,
  }) {
    return http.post(
      Uri.parse('$baseUrl/employee-details'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'emp_id': empId,
        'auth_token': authToken,
      }),
    );
  }

  /// 8. Fetch Employee Photo
  static Future<http.Response> fetchEmployeePhoto({
    required String photoUrl,
    required String authToken,
  }) {
    return http.get(
      Uri.parse(photoUrl),
      headers: {'Authorization': 'Bearer $authToken'},
    );
  }

  /// 9. Send Location Update (Location Tracker)
  static Future<http.Response> sendLocationUpdate(Map<String, dynamic> payload) {
    return http.post(
      Uri.parse('$baseUrl/locationtracker'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
  }

  /// 10. Fetch Shifts
  static Future<http.Response> fetchShifts({
    required String empId,
    required String authToken,
  }) {
    return http.post(
      Uri.parse('$baseUrl/shifts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'emp_code': empId,
        'auth_token': authToken,
      }),
    );
  }

  /// 11. Fetch Status
  static Future<http.Response> fetchStatus({
    required String empId,
    required String authToken,
  }) {
    return http.post(
      Uri.parse('$baseUrlAlt/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'emp_id': empId,
        'auth_token': authToken,
      }),
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
    return http.post(
      Uri.parse('$baseUrl/checkin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'auth_token': authToken,
        'emp_id': empId,
        'shift_id': shiftId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
        'device_serial_number': deviceSerialNumber,
      }),
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
    return http.post(
      Uri.parse('$baseUrlAlt/checkout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'auth_token': authToken,
        'emp_id': empId,
        'shift_id': shiftId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
        'device_serial_number': deviceSerialNumber,
      }),
    );
  }

  /// 14. Update Request Status (Admin)
  static Future<http.Response> updateRequestStatus({
    required String url,
    required String authToken,
    required Map<String, dynamic> body,
  }) {
    return http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );
  }

  /// 15. Fetch Pending Requests (Admin)
  static Future<http.Response> fetchPendingRequests({
    required String authToken,
  }) {
    return http.post(
      Uri.parse('$baseUrl/pending-requests'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({'auth_token': authToken}),
    ).timeout(const Duration(seconds: 10));
  }

  /// 16. Fetch Tasks
  static Future<http.Response> fetchTasks({
    required String authToken,
  }) {
    return http.get(
      Uri.parse('$baseUrl/tasks'),
      headers: {
        'Authorization': 'Bearer $authToken',
      },
    );
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
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/taskreport'),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $authToken',
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

    return request.send();
  }

  /// 18. Submit Work Sheet Entry
  static Future<http.Response> submitWorkUpdate({
    required Map<String, dynamic> body,
  }) {
    return http.post(
      Uri.parse('$baseUrl/sheet/create'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }
}
