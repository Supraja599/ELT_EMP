import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

class LeaveScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;

  const LeaveScreen({
    Key? key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId, // ✅ REQUIRED

  }) : super(key: key);

  @override
  _LeaveScreenState createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String? selectedLeaveTypeId;
  bool _isSubmitting = false;
  final Set<String> _submittedLeaves = {};

  final List<Map<String, String>> leaveTypes = [
    {"id": "1", "label": "Casual Leave"},
    {"id": "2", "label": "Comp Off Leave"},
    {"id": "3", "label": "Earned Leave"},
  ];

  /// Check internet connectivity
  Future<bool> _hasInternet() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Intercept back press and show popup
  Future<bool> _onWillPop() async {
    bool? exit = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Go Back?"),
        content: const Text(
            "Are you sure you want to go back to CheckInOutScreen?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (exit == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CheckInOutScreen(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId, // ✅ ADD
            deviceSerialNumber:  widget.deviceSerialNumber,

          ),
        ),
            (route) => false,
      );
      return false;
    }
    return false;
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController controller) async {
    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      controller.text = picked.toIso8601String().split('T')[0];
    }
  }

  Future<void> _submitLeave() async {
    if (_isSubmitting) return;

    // Check internet before submitting
    bool hasInternet = await _hasInternet();
    if (!hasInternet) {
      _showNoInternetDialog();
      return;
    }

    if (_fromDateController.text.isEmpty ||
        _toDateController.text.isEmpty ||
        selectedLeaveTypeId == null ||
        _reasonController.text.isEmpty) {
      _showDialog("Failed", "Please fill all fields.");
      return;
    }

    DateTime fromDate = DateTime.parse(_fromDateController.text);
    DateTime toDate = DateTime.parse(_toDateController.text);

    if (fromDate.isAfter(toDate)) {
      _showDialog("Failed", "From date cannot be after To date.");
      return;
    }

    if (fromDate.isBefore(DateTime.now().subtract(const Duration(days: 1))) ||
        toDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      _showDialog("Invalid Date", "You cannot apply for leave in the past.");
      return;
    }

    final String leaveKey =
        '${widget.empId}_${_fromDateController.text}_${_toDateController.text}_$selectedLeaveTypeId';

    if (_submittedLeaves.contains(leaveKey)) {
      _showDialog("Duplicate", "Leave already submitted for these dates.");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final response = await ApiService.applyLeave(
        authToken: widget.authToken,
        empId: widget.empId,
        leaveTypeId: selectedLeaveTypeId!,
        fromDate: _fromDateController.text,
        toDate: _toDateController.text,
        reason: _reasonController.text,
      );

      final result = jsonDecode(response.body);

      if (result["status"] == "success") {
        _submittedLeaves.add(leaveKey);
        _showDialog(
            "Success", result["message"] ?? "Leave applied successfully");
      } else {
        _showDialog("Failed", result["message"] ?? "Something went wrong");
      }
    } catch (e) {
      _showDialog("Failed", "Could not apply leave. Try again later.");
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showNoInternetDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No Internet"),
        content: const Text("Please check your internet connection."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _submitLeave(); // Retry
            },
            child: const Text("Retry"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Optionally, go offline / just stay
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          ElevatedButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
      prefixIcon: Icon(prefixIcon, color: Colors.teal.shade700),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  IconData _getLeaveTypeIcon(String id) {
    switch (id) {
      case '1':
        return Icons.beach_access_rounded; // Casual
      case '2':
        return Icons.coffee_rounded; // Comp Off
      case '3':
      default:
        return Icons.stars_rounded; // Earned
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop, // intercept back button
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text(
            "Apply Leave",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
            onPressed: () => _onWillPop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              // ── FORM CONTAINER CARD ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Leave Request Form",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // From Date Field
                    TextField(
                      controller: _fromDateController,
                      readOnly: true,
                      decoration: _buildInputDecoration(
                        labelText: "From Date",
                        prefixIcon: Icons.calendar_today_rounded,
                      ),
                      onTap: () => _selectDate(context, _fromDateController),
                    ),
                    const SizedBox(height: 20),

                    // To Date Field
                    TextField(
                      controller: _toDateController,
                      readOnly: true,
                      decoration: _buildInputDecoration(
                        labelText: "To Date",
                        prefixIcon: Icons.calendar_today_rounded,
                      ),
                      onTap: () => _selectDate(context, _toDateController),
                    ),
                    const SizedBox(height: 20),

                    // Leave Type Dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: _buildInputDecoration(
                        labelText: "Leave Type",
                        prefixIcon: Icons.category_rounded,
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      items: leaveTypes.map((type) {
                        return DropdownMenuItem(
                          value: type["id"],
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Icon(
                                _getLeaveTypeIcon(type["id"]!),
                                color: Colors.teal.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  type["label"]!,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedLeaveTypeId = value;
                        });
                      },
                      value: selectedLeaveTypeId,
                    ),
                    const SizedBox(height: 20),

                    // Reason Field
                    TextField(
                      controller: _reasonController,
                      maxLines: 4,
                      decoration: _buildInputDecoration(
                        labelText: "Reason for Leave",
                        prefixIcon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitLeave,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green.shade700, Colors.teal.shade500],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.send_rounded, color: Colors.white),
                                        SizedBox(width: 10),
                                        Text(
                                          "Submit Leave Request",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
