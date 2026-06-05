import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // Replace with your actual splash/login screen import
import 'services/api_service.dart';

class EmpProfile extends StatefulWidget {
  final String empId;
  final String authToken;

  const EmpProfile({
    super.key,
    required this.empId,
    required this.authToken,
    required String empName,
  });

  @override
  State<EmpProfile> createState() => _EmpProfileState();
}

class _EmpProfileState extends State<EmpProfile> {
  Map<String, dynamic>? cachedEmp;
  Uint8List? cachedPhoto;
  late Future<Map<String, dynamic>> empDetailsFuture;

  @override
  void initState() {
    super.initState();
    _loadCachedEmployee();
    empDetailsFuture = fetchEmployeeDetails();
  }

  Future<void> _loadCachedEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    final empJson = prefs.getString('emp_${widget.empId}');
    if (empJson != null) {
      setState(() {
        cachedEmp = jsonDecode(empJson);
      });
      final photoUrl = cachedEmp?['photo'] ?? '';
      if (photoUrl.isNotEmpty) {
        _loadCachedPhoto(photoUrl);
      }
    }
  }

  Future<void> _loadCachedPhoto(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'emp_photo_${widget.empId}';
      final cachedBytes = prefs.getString(key);
      if (cachedBytes != null) {
        setState(() {
          cachedPhoto = base64Decode(cachedBytes);
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> fetchEmployeeDetails() async {
    final response = await ApiService.fetchEmployeeDetails(
      empId: widget.empId,
      authToken: widget.authToken,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final empDetails = data['employee_details'];
        if (empDetails != null && empDetails is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('emp_${widget.empId}', jsonEncode(empDetails));

          // Load photo
          final photoUrl = empDetails['photo']?.toString() ?? '';
          if (photoUrl.isNotEmpty) {
            final bytes = await fetchEmployeePhoto(photoUrl);
            if (bytes != null) {
              prefs.setString('emp_photo_${widget.empId}', base64Encode(bytes));
              setState(() => cachedPhoto = bytes);
            }
          }

          if (mounted) setState(() => cachedEmp = empDetails);
          return empDetails;
        } else {
          throw Exception('Employee details are null or invalid in response');
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to fetch details');
      }
    } else {
      throw Exception('Failed to fetch employee details');
    }
  }

  Future<Uint8List?> fetchEmployeePhoto(String url) async {
    try {
      final response = await ApiService.fetchEmployeePhoto(
        photoUrl: url,
        authToken: widget.authToken,
      );
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<void> _logout({bool showConfirmation = true}) async {
    if (showConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Logout Confirmation'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ) ??
      false;

      if (!confirmed) return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _forceLoginAgain() async {
    await _logout(showConfirmation: false);
  }

  @override
  Widget build(BuildContext context) {
    final emp = cachedEmp;

    if (emp != null) {
      return _buildEmployeeContent(emp);
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: empDetailsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Session expired or failed to load details.\nPlease login again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.red),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Login Again'),
                    onPressed: _forceLoginAgain,
                  ),
                ],
              ),
            ),
          );
        } else if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: Text('No employee details found')));
        }

        return _buildEmployeeContent(snapshot.data!);
      },
    );
  }

  Widget _buildEmployeeContent(Map<String, dynamic> emp) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(), // Prevent bouncy scroll
        child: Column(
          children: [
                    // ── CURVED GRADIENT HEADER & OVERLAPPING AVATAR ──────────
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green.shade600, Colors.teal.shade500],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 12,
                            left: 20,
                            right: 20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 52), // Balance spacing
                              const Text(
                                'Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: const [
                                  Icon(Icons.notifications_rounded, color: Colors.white, size: 24),
                                  SizedBox(width: 12),
                                  Icon(Icons.settings_rounded, color: Colors.white, size: 24),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: -40,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.teal.shade700.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.teal.shade50,
                                backgroundImage: cachedPhoto != null ? MemoryImage(cachedPhoto!) : null,
                                child: cachedPhoto == null
                                    ? Text(
                                        emp['name'] != null && emp['name'].toString().isNotEmpty
                                            ? emp['name'].toString()[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 32,
                                          color: Colors.teal.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 52),

                    // ── NAME & DESIGNATION ───────────────────────────────────
                    Text(
                      emp['name'] != null ? emp['name'].toString().toUpperCase() : 'Not Available',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      emp['designation'] != null && emp['designation'].toString().isNotEmpty
                          ? emp['designation'].toString()
                          : 'Employee',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // ── GRID OF DETAILED CARDS ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.35, // Wider cards to fit screen height
                        children: [
                          _buildGridCard(Icons.badge_rounded, 'Employee ID', emp['employee_id']),
                          _buildGridCard(Icons.call_rounded, 'Contact Number', emp['contact_number']),
                          _buildGridCard(Icons.email_rounded, 'Email Address', emp['email']),
                          _buildGridCard(Icons.business_center_rounded, 'Designation', emp['designation']),
                          _buildGridCard(Icons.account_tree_rounded, 'Department', emp['department']),
                          _buildGridCard(Icons.calendar_today_rounded, 'Date of Joining', emp['doj']),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── ACTION BUTTONS ───────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade500,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 1,
                              ),
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                              label: const Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _logout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade500,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 1,
                              ),
                              icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                              label: const Text(
                                'Logout',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
    );
  }

  Widget _buildGridCard(IconData icon, String title, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.teal.shade700, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value != null && value.toString().isNotEmpty ? value.toString() : 'N/A',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}