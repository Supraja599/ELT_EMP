import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

class ExpensesScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;

  const ExpensesScreen({
    Key? key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId, // ✅ REQUIRED

  }) : super(key: key);

  @override
  _ExpensesScreenState createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  File? _receiptImage;
  bool _loading = false;
  bool _showAllExpenses = false;

  List<Map<String, dynamic>> _expenses = [];

  Widget _buildStatusBadge(String? status) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText = status ?? 'pending';

    switch (statusText.toLowerCase()) {
      case 'approved':
      case '1':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        icon = Icons.check_circle_rounded;
        statusText = 'Approved';
        break;
      case 'rejected':
      case '2':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        icon = Icons.cancel_rounded;
        statusText = 'Rejected';
        break;
      case 'pending':
      default:
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade800;
        icon = Icons.hourglass_bottom_rounded;
        statusText = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkInternetAndFetch();
  }

  /// Check internet connectivity
  Future<bool> _hasInternet() async {
    var result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Show no internet popup
  void _showNoInternetDialog(Function retryAction) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No Internet"),
        content: const Text("Please check your internet connection."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              retryAction(); // Retry action
            },
            child: const Text("Retry"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<void> _checkInternetAndFetch() async {
    bool connected = await _hasInternet();
    if (connected) {
      _fetchExpenses();
    } else {
      _showNoInternetDialog(_checkInternetAndFetch);
    }
  }

  /// Intercept back press to show popup
  Future<bool> _onWillPop() async {
    bool? exit = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Go Back?"),
        content: const Text(
            "Are you sure you want to go back to CheckInOutScreen?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Stay
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Go back
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

  Future<void> _fetchExpenses() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.fetchExpenses();
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() => _expenses = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      _showNoInternetDialog(_fetchExpenses);
    }
    setState(() => _loading = false);
  }

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _receiptImage = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    bool connected = await _hasInternet();
    if (!connected) {
      _showNoInternetDialog(_submit);
      return;
    }

    setState(() => _loading = true);

    try {
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
      final description = _descCtrl.text.trim();
      final date = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final receiptBase64 = _receiptImage != null ? base64Encode(await _receiptImage!.readAsBytes()) : null;

      final res = await ApiService.submitExpense(
        amount: amount,
        description: description,
        date: date,
        receiptBase64: receiptBase64,
      );

      setState(() => _loading = false);

      if (res.statusCode == 201) {
        _amountCtrl.clear();
        _descCtrl.clear();
        setState(() {
          _selectedDate = DateTime.now();
          _receiptImage = null;
        });
        await _fetchExpenses();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Expense submitted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit expense')),
        );
      }
    } on TimeoutException {
      setState(() => _loading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Timeout'),
          content: Text('Submission is taking too long. Click OK to retry.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _amountCtrl.clear();
                _descCtrl.clear();
                setState(() {
                  _selectedDate = DateTime.now();
                  _receiptImage = null;
                });
              },
              child: Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting expense')),
      );
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text(
            "Expenses",
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Submit Expense Claim",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Amount Field
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _buildInputDecoration(
                          labelText: "Amount",
                          prefixIcon: Icons.currency_rupee_rounded,
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),

                      // Description Field
                      TextFormField(
                        controller: _descCtrl,
                        decoration: _buildInputDecoration(
                          labelText: "Description",
                          prefixIcon: Icons.notes_rounded,
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),

                      // Date Picker Trigger
                      GestureDetector(
                        onTap: () async {
                          final dt = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (dt != null) setState(() => _selectedDate = dt);
                        },
                        child: InputDecorator(
                          decoration: _buildInputDecoration(
                            labelText: "Select Date",
                            prefixIcon: Icons.calendar_today_rounded,
                          ),
                          child: Text(
                            DateFormat('yyyy-MM-dd').format(_selectedDate),
                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Receipt Row
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.image_rounded, color: Colors.white),
                            label: const Text('Pick Receipt', style: TextStyle(color: Colors.white)),
                            onPressed: _pickReceipt,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (_receiptImage != null)
                            Row(
                              children: const [
                                Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                                SizedBox(width: 4),
                                Text(
                                  'Selected',
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
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
                              child: _loading
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
                                            "Submit Expense Claim",
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
              ),
              const SizedBox(height: 30),

              // ── SUBMITTED EXPENSES SECTION ───────────────────────────
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Submitted Expenses',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading && _expenses.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_expenses.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  alignment: Alignment.center,
                  child: Column(
                    children: const [
                      Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No expenses found.',
                        style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              else ...[
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _showAllExpenses ? _expenses.length : (_expenses.length > 2 ? 2 : _expenses.length),
                  itemBuilder: (_, i) {
                    final e = _expenses[i];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.currency_rupee_rounded, color: Colors.teal.shade700, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '₹ ${e['amount']}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade800,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusBadge(e['status']),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    e['description'],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              e['date'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_expenses.length > 2) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAllExpenses = !_showAllExpenses;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.teal.shade600, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: Icon(
                        _showAllExpenses ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: Colors.teal.shade700,
                        size: 18,
                      ),
                      label: Text(
                        _showAllExpenses ? "Show Less" : "View More",
                        style: TextStyle(
                          color: Colors.teal.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
