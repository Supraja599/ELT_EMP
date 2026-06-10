import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class VHSOvertimeScreen extends StatefulWidget {
  final String empId;
  final String authToken;
  final String empName;
  final List<Map<String, dynamic>> empShifts;

  const VHSOvertimeScreen({
    super.key,
    required this.empId,
    required this.authToken,
    required this.empName,
    required this.empShifts,
  });

  @override
  State<VHSOvertimeScreen> createState() => _VHSOvertimeScreenState();
}

class _VHSOvertimeScreenState extends State<VHSOvertimeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Submit form state ────────────────────────────────────────────────────
  final _dateCtrl      = TextEditingController();
  final _checkinCtrl   = TextEditingController();
  final _checkoutCtrl  = TextEditingController();
  final _otMinCtrl     = TextEditingController();

  DateTime? _selectedDate;
  DateTime? _checkinDateTime;
  DateTime? _checkoutDateTime;
  String?   _selectedShiftId;
  bool _isSubmitting = false;

  // ── History state ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _records = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _records.isEmpty) {
        _fetchHistory();
      }
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
    _otMinCtrl.dispose();
    super.dispose();
  }

  // ── Pick Date ─────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      // Reset check-in/out when date changes
      _checkinDateTime = null;
      _checkoutDateTime = null;
      _checkinCtrl.clear();
      _checkoutCtrl.clear();
      _otMinCtrl.clear();
    });
  }

  // ── Pick DateTime (date already fixed, just pick time) ───────────────────
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

    // If checkout is before or same as checkin, assume next day
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
      _autoCalcOtMinutes();
    });
  }

  void _autoCalcOtMinutes() {
    if (_checkinDateTime != null && _checkoutDateTime != null) {
      final diff = _checkoutDateTime!.difference(_checkinDateTime!).inMinutes;
      if (diff > 0) _otMinCtrl.text = diff.toString();
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedShiftId == null) {
      _snack('Please select a shift', isError: true); return;
    }
    if (_checkinDateTime == null) {
      _snack('Please select check-in time', isError: true); return;
    }
    if (_checkoutDateTime == null) {
      _snack('Please select check-out time', isError: true); return;
    }
    final otMin = int.tryParse(_otMinCtrl.text.trim());
    if (otMin == null || otMin <= 0) {
      _snack('Please enter valid OT minutes', isError: true); return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiService.createOvertimeVHS(
        authToken: widget.authToken,
        empId: widget.empId,
        date: _dateCtrl.text,
        shiftId: _selectedShiftId!,
        checkinTime: _checkinCtrl.text,
        checkoutTime: _checkoutCtrl.text,
        otMinutes: otMin,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _snack(data['message'] ?? 'Overtime request submitted successfully.');
        // Reset form
        setState(() {
          _selectedShiftId = null;
          _checkinDateTime = null;
          _checkoutDateTime = null;
          _checkinCtrl.clear();
          _checkoutCtrl.clear();
          _otMinCtrl.clear();
        });
        // Refresh history and switch to it
        await _fetchHistory();
        _tabController.animateTo(1);
      } else {
        _snack(data['message'] ?? 'Failed to submit', isError: true);
      }
    } catch (_) {
      _snack('Network error. Please try again.', isError: true);
    }
    setState(() => _isSubmitting = false);
  }

  // ── Fetch History ─────────────────────────────────────────────────────────
  Future<void> _fetchHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final response = await ApiService.fetchOvertimeListVHS(
        authToken: widget.authToken,
        empId: widget.empId,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final List raw = data['overtime_records'] ?? [];
        setState(() {
          _records = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    setState(() => _isLoadingHistory = false);
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
          'Overtime Request',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purple,
          labelColor: Colors.purple,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Submit OT'),
            Tab(icon: Icon(Icons.history_rounded),    text: 'OT Records'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSubmitTab(), _buildHistoryTab()],
      ),
    );
  }

  // ── Submit Tab ─────────────────────────────────────────────────────────────
  Widget _buildSubmitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.purple, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Submit your overtime request for manager approval. OT minutes are auto-calculated from your selected times.',
                    style: TextStyle(fontSize: 13, color: Colors.purple),
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
                const Text('OT Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // Date
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _dateCtrl,
                      decoration: _inputDeco('Date *', Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Shift
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedShiftId),
                  initialValue: _selectedShiftId,
                  hint: const Text('Select Shift'),
                  decoration: InputDecoration(
                    labelText: 'Shift *',
                    prefixIcon: Icon(Icons.badge_rounded, color: Colors.purple.shade400, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.purple.shade400, width: 1.5)),
                    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  items: widget.empShifts.map((s) => DropdownMenuItem<String>(
                    value: s['id']?.toString() ?? '',
                    child: Text(s['name']?.toString() ?? ''),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedShiftId = v),
                ),
                const SizedBox(height: 16),

                // Check-in time
                GestureDetector(
                  onTap: () => _pickTime(isCheckin: true),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _checkinCtrl,
                      decoration: _inputDeco('Check-in Time *', Icons.login_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Check-out time
                GestureDetector(
                  onTap: () => _pickTime(isCheckin: false),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _checkoutCtrl,
                      decoration: _inputDeco('Check-out Time *', Icons.logout_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // OT Minutes
                TextField(
                  controller: _otMinCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDeco('OT Minutes *  (auto-calculated)', Icons.timer_rounded),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit for Approval',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.purple.shade400, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.purple.shade400, width: 1.5)),
    );
  }

  // ── History Tab ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.purple));
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No overtime records yet', style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh_rounded, color: Colors.purple),
              label: const Text('Refresh', style: TextStyle(color: Colors.purple)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: Colors.purple,
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _records.length,
        itemBuilder: (_, i) => _buildRecordCard(_records[i]),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> rec) {
    final date      = rec['date']?.toString() ?? '';
    final shiftName = rec['shift_name']?.toString() ?? '';
    final shiftTime = rec['shift_time']?.toString() ?? '';
    final checkin   = rec['checkin_time']?.toString() ?? '';
    final checkout  = rec['checkout_time']?.toString() ?? '';
    final otMin     = rec['ot_minutes']?.toString() ?? '0';
    final status    = (rec['status']?.toString() ?? 'pending').toLowerCase();
    final createdAt = rec['created_at']?.toString() ?? '';

    Color statusColor;
    switch (status) {
      case 'approved': statusColor = Colors.green; break;
      case 'rejected': statusColor = Colors.red;   break;
      default:         statusColor = Colors.orange;
    }

    String displayDate = date;
    try { displayDate = DateFormat('dd MMM yyyy').format(DateTime.parse(date)); } catch (_) {}

    String displayCheckin  = _formatTime(checkin);
    String displayCheckout = _formatTime(checkout);

    final hours = int.tryParse(otMin) ?? 0;
    final hh = hours ~/ 60;
    final mm = hours % 60;
    final otDisplay = hh > 0 ? '${hh}h ${mm}m' : '${mm}m';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.more_time_rounded, color: Colors.purple.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                      if (shiftName.isNotEmpty)
                        Text('$shiftName  $shiftTime', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
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
              children: [
                Row(
                  children: [
                    _infoChip(Icons.login_rounded, 'In', displayCheckin, Colors.green),
                    const SizedBox(width: 8),
                    _infoChip(Icons.logout_rounded, 'Out', displayCheckout, Colors.red),
                    const SizedBox(width: 8),
                    _infoChip(Icons.timer_rounded, 'OT', otDisplay, Colors.purple),
                  ],
                ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Submitted: ${_formatCreatedAt(createdAt)}',
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

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatCreatedAt(String raw) {
    try {
      return DateFormat('dd MMM, hh:mm a').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }
}
