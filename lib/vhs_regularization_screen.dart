import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class VHSRegularizationScreen extends StatefulWidget {
  final String empId;
  final String authToken;
  final String empName;

  const VHSRegularizationScreen({
    super.key,
    required this.empId,
    required this.authToken,
    required this.empName,
  });

  @override
  State<VHSRegularizationScreen> createState() => _VHSRegularizationScreenState();
}

class _VHSRegularizationScreenState extends State<VHSRegularizationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Submit form state ────────────────────────────────────────────────────
  final _dateCtrl     = TextEditingController();
  final _checkinCtrl  = TextEditingController();
  final _checkoutCtrl = TextEditingController();
  final _reasonCtrl   = TextEditingController();

  DateTime? _selectedDate;
  DateTime? _checkinDateTime;
  DateTime? _checkoutDateTime;
  bool _isSubmitting = false;

  // ── History state ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _records = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _records.isEmpty) _fetchHistory();
    });
    final now = DateTime.now();
    _selectedDate = now;
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(now);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateCtrl.dispose();
    _checkinCtrl.dispose();
    _checkoutCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Pickers ───────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      _checkinDateTime = null;
      _checkoutDateTime = null;
      _checkinCtrl.clear();
      _checkoutCtrl.clear();
    });
  }

  Future<void> _pickTime({required bool isCheckin}) async {
    final baseDate = _selectedDate ?? DateTime.now();
    final initial = isCheckin
        ? (_checkinDateTime ?? baseDate)
        : (_checkoutDateTime ?? _checkinDateTime ?? baseDate);

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (time == null) return;

    DateTime dt = DateTime(baseDate.year, baseDate.month, baseDate.day, time.hour, time.minute);
    // If checkout is before/equal to checkin, assume next day
    if (!isCheckin && _checkinDateTime != null && !dt.isAfter(_checkinDateTime!)) {
      dt = dt.add(const Duration(days: 1));
    }

    setState(() {
      if (isCheckin) {
        _checkinDateTime = dt;
        _checkinCtrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
      } else {
        _checkoutDateTime = dt;
        _checkoutCtrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_checkinDateTime == null) {
      _snack('Please select requested check-in time', isError: true); return;
    }
    if (_checkoutDateTime == null) {
      _snack('Please select requested check-out time', isError: true); return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      _snack('Please enter a reason', isError: true); return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await ApiService.applyRegularization(
        authToken: widget.authToken,
        empId: widget.empId,
        attendanceDate: _dateCtrl.text,
        requestedCheckin: _checkinCtrl.text,
        requestedCheckout: _checkoutCtrl.text,
        reason: _reasonCtrl.text.trim(),
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        _snack(data['message'] ?? 'Regularization request submitted successfully.');
        setState(() {
          final now = DateTime.now();
          _selectedDate = now;
          _dateCtrl.text = DateFormat('yyyy-MM-dd').format(now);
          _checkinDateTime = null;
          _checkoutDateTime = null;
          _checkinCtrl.clear();
          _checkoutCtrl.clear();
          _reasonCtrl.clear();
        });
        await _fetchHistory();
        _tabController.animateTo(1);
      } else {
        _snack(data['message'] ?? 'Failed to submit', isError: true);
      }
    } catch (_) {
      _snack('Network error. Please try again.', isError: true);
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  // ── History ───────────────────────────────────────────────────────────────
  Future<void> _fetchHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final res = await ApiService.fetchRegularizationStatus(
        authToken: widget.authToken,
        empId: widget.empId,
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        final List raw = data['requests'] ?? [];
        setState(() {
          _records = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingHistory = false);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Regularization',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.indigo,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.edit_calendar_rounded), text: 'Apply'),
            Tab(icon: Icon(Icons.history_rounded),        text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildApplyTab(), _buildHistoryTab()],
      ),
    );
  }

  // ── Apply Tab ──────────────────────────────────────────────────────────────
  Widget _buildApplyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.indigo, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Apply regularization if you missed check-in or check-out. Your request will be reviewed by the admin.',
                    style: TextStyle(fontSize: 13, color: Colors.indigo),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Form card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attendance Details',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // Attendance Date
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _dateCtrl,
                      decoration: _inputDeco('Attendance Date *', Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Requested Check-in
                GestureDetector(
                  onTap: () => _pickTime(isCheckin: true),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _checkinCtrl,
                      decoration: _inputDeco('Requested Check-in *', Icons.login_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Requested Check-out
                GestureDetector(
                  onTap: () => _pickTime(isCheckin: false),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _checkoutCtrl,
                      decoration: _inputDeco('Requested Check-out *', Icons.logout_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Reason
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: _inputDeco('Reason *', Icons.notes_rounded),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit Request',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── History Tab ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.indigo));
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No regularization records yet',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh_rounded, color: Colors.indigo),
              label: const Text('Refresh', style: TextStyle(color: Colors.indigo)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: Colors.indigo,
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _records.length,
        itemBuilder: (_, i) => _buildRecordCard(_records[i]),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> rec) {
    final attendanceDate  = rec['attendance_date']?.toString() ?? '';
    final reqCheckin      = rec['requested_checkin']?.toString() ?? '';
    final reqCheckout     = rec['requested_checkout']?.toString() ?? '';
    final reason          = rec['reason']?.toString() ?? '';
    final status          = (rec['status']?.toString() ?? 'pending').toLowerCase();
    final createdAt       = rec['created_at']?.toString() ?? '';

    Color statusColor;
    switch (status) {
      case 'approved': statusColor = Colors.green; break;
      case 'rejected': statusColor = Colors.red;   break;
      default:         statusColor = Colors.orange;
    }

    String displayDate = attendanceDate;
    try { displayDate = DateFormat('dd MMM yyyy').format(DateTime.parse(attendanceDate)); } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.edit_calendar_rounded, color: Colors.indigo.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayDate,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _infoChip(Icons.login_rounded,  'Check-in',  _fmtTime(reqCheckin),  Colors.green),
                    const SizedBox(width: 8),
                    _infoChip(Icons.logout_rounded, 'Check-out', _fmtTime(reqCheckout), Colors.red),
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes_rounded, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(reason,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ),
                    ],
                  ),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Submitted: ${_fmtCreatedAt(createdAt)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 11, color: Colors.black87), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.indigo, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.indigo.shade400, width: 1.5)),
    );
  }

  String _fmtTime(String raw) {
    try { return DateFormat('hh:mm a').format(DateTime.parse(raw).toLocal()); } catch (_) { return raw; }
  }

  String _fmtCreatedAt(String raw) {
    try { return DateFormat('dd MMM, hh:mm a').format(DateTime.parse(raw).toLocal()); } catch (_) { return raw; }
  }
}
