import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class _ShiftOption {
  final String id;
  final String name;      // raw name sent to API, e.g. "A Shift"
  final String startTime; // "HH:MM:SS"
  final String endTime;   // "HH:MM:SS"
  final String display;   // shown in dropdown

  const _ShiftOption({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.display,
  });

  @override
  bool operator ==(Object other) => other is _ShiftOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

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
  State<VHSRegularizationScreen> createState() =>
      _VHSRegularizationScreenState();
}

class _VHSRegularizationScreenState extends State<VHSRegularizationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Submit form state ──────────────────────────────────────────────────────
  final _dateCtrl   = TextEditingController();
  final _reasonCtrl = TextEditingController();

  DateTime? _selectedDate;
  _ShiftOption? _selectedShift;
  bool _isSubmitting    = false;
  bool _isLoadingShifts = true;
  List<_ShiftOption> _shiftOptions = [];

  // ── History state ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _records       = [];
  bool                       _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _records.isEmpty) _fetchHistory();
    });
    final now = DateTime.now();
    _selectedDate    = now;
    _dateCtrl.text   = DateFormat('yyyy-MM-dd').format(now);
    _loadShifts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Load shifts from API, fall back to defaults ────────────────────────────
  Future<void> _loadShifts() async {
    setState(() => _isLoadingShifts = true);
    try {
      final res  = await ApiService.fetchShifts(
          empId: widget.empId, authToken: widget.authToken);
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        final List raw = data['shifts'] ?? [];
        final List<_ShiftOption> opts = [];
        for (final shift in raw) {
          final rawTime = shift['shift_time']?.toString() ?? '';
          var   name    = shift['shift_name']?.toString() ?? '';
          if (name.trim().toLowerCase() == 'open shift') name = 'General Shift';

          String start   = '09:00:00';
          String end     = '17:00:00';
          String display = name;

          if (RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$').hasMatch(rawTime)) {
            final parts = rawTime.split('-');
            start   = '${parts[0].trim()}:00';
            end     = '${parts[1].trim()}:00';
            display = '$name  (${_toAmPm(parts[0].trim())} – ${_toAmPm(parts[1].trim())})';
          }

          opts.add(_ShiftOption(
            id:        shift['id']?.toString() ?? '',
            name:      name,
            startTime: start,
            endTime:   end,
            display:   display,
          ));
        }
        if (opts.isNotEmpty) {
          setState(() {
            _shiftOptions  = opts;
            _selectedShift = opts.first;
          });
          return;
        }
      }
    } catch (_) {}
    // Fallback
    final defaults = _defaultShifts();
    setState(() {
      _shiftOptions  = defaults;
      _selectedShift = defaults.first;
    });
  }

  List<_ShiftOption> _defaultShifts() => [
        _ShiftOption(
            id: '1', name: 'General Shift',
            startTime: '09:00:00', endTime: '17:00:00',
            display: 'General Shift  (09:00 AM – 05:00 PM)'),
        _ShiftOption(
            id: '2', name: 'A Shift',
            startTime: '06:00:00', endTime: '14:00:00',
            display: 'A Shift  (06:00 AM – 02:00 PM)'),
        _ShiftOption(
            id: '3', name: 'B Shift',
            startTime: '14:00:00', endTime: '22:00:00',
            display: 'B Shift  (02:00 PM – 10:00 PM)'),
        _ShiftOption(
            id: '4', name: 'C Shift',
            startTime: '22:00:00', endTime: '06:00:00',
            display: 'C Shift  (10:00 PM – 06:00 AM)'),
      ];

  String _toAmPm(String hhmm) {
    try {
      final parts  = hhmm.split(':');
      int   h      = int.parse(parts[0]);
      final m      = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h > 12) h -= 12;
      if (h == 0) h = 12;
      return '$h:$m $period';
    } catch (_) {
      return hhmm;
    }
  }

  // ── Date Picker ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate:   DateTime.now().subtract(const Duration(days: 90)),
      lastDate:    DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate  = picked;
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
    });
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedShift == null) {
      _snack('Please select a shift', isError: true);
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      _snack('Please enter a reason', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res  = await ApiService.applyRegularization(
        authToken:      widget.authToken,
        empId:          widget.empId,
        attendanceDate: _dateCtrl.text,
        shiftName:      _selectedShift!.name,
        startTime:      _selectedShift!.startTime,
        shiftEnd:       _selectedShift!.endTime,
        reason:         _reasonCtrl.text.trim(),
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        _snack(data['message'] ?? 'Regularization request submitted successfully.');
        setState(() {
          final now      = DateTime.now();
          _selectedDate  = now;
          _dateCtrl.text = DateFormat('yyyy-MM-dd').format(now);
          if (_shiftOptions.isNotEmpty) _selectedShift = _shiftOptions.first;
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

  // ── History ────────────────────────────────────────────────────────────────
  Future<void> _fetchHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final res  = await ApiService.fetchRegularizationStatus(
          authToken: widget.authToken, empId: widget.empId);
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

  // ── Build ──────────────────────────────────────────────────────────────────
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
            Tab(icon: Icon(Icons.history_rounded),       text: 'History'),
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
              color:        Colors.indigo.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.indigo, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Apply regularization if you missed check-in or check-out. '
                    'Your request will be reviewed by the admin.',
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
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset:     const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance Details',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // ── Attendance Date picker ───────────────────────────────────
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _dateCtrl,
                      decoration: _inputDeco(
                          'Attendance Date *', Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Shift dropdown ───────────────────────────────────────────
                _isLoadingShifts
                    ? Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color:        const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border:       Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width:  20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.indigo),
                          ),
                        ),
                      )
                    : DropdownButtonFormField<_ShiftOption>(
                        key:          ValueKey(_selectedShift?.id),
                        initialValue: _selectedShift,
                        isExpanded:   true,
                        decoration: _inputDeco(
                            'Select Shift *', Icons.work_history_rounded),
                        items: _shiftOptions
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.display,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedShift = val),
                        dropdownColor: Colors.white,
                      ),
                const SizedBox(height: 16),

                // ── Shift time preview chips ─────────────────────────────────
                if (_selectedShift != null)
                  Row(
                    children: [
                      Expanded(
                        child: _timeChip(
                          Icons.login_rounded,
                          'Shift Start',
                          _fmtHhmmss(_selectedShift!.startTime),
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeChip(
                          Icons.logout_rounded,
                          'Shift End',
                          _fmtHhmmss(_selectedShift!.endTime),
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                if (_selectedShift != null) const SizedBox(height: 16),

                // ── Reason ───────────────────────────────────────────────────
                TextField(
                  controller: _reasonCtrl,
                  maxLines:   3,
                  decoration: _inputDeco('Reason *', Icons.notes_rounded),
                ),
                const SizedBox(height: 24),

                // ── Submit button ────────────────────────────────────────────
                SizedBox(
                  width:  double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width:  20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit Request',
                      style: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.bold,
                          color:      Colors.white),
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

  Widget _timeChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: color, fontWeight: FontWeight.bold)),
              Text(value,
                  style: const TextStyle(
                      fontSize:   13,
                      color:      Colors.black87,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ── History Tab ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.indigo));
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
              icon:  const Icon(Icons.refresh_rounded, color: Colors.indigo),
              label: const Text('Refresh',
                  style: TextStyle(color: Colors.indigo)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color:     Colors.indigo,
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding:     const EdgeInsets.all(16),
        itemCount:   _records.length,
        itemBuilder: (_, i) => _buildRecordCard(_records[i]),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> rec) {
    final attendanceDate = rec['attendance_date']?.toString() ?? '';
    final shiftName      = rec['shift_name']?.toString() ?? '';
    final startTime      = rec['start_time']?.toString()
        ?? rec['requested_checkin']?.toString() ?? '';
    final shiftEnd       = rec['shift_end']?.toString()
        ?? rec['requested_checkout']?.toString() ?? '';
    final reason         = rec['reason']?.toString() ?? '';
    final status         =
        (rec['status']?.toString() ?? 'pending').toLowerCase();
    final createdAt      = rec['created_at']?.toString() ?? '';

    Color statusColor;
    switch (status) {
      case 'approved': statusColor = Colors.green; break;
      case 'rejected': statusColor = Colors.red;   break;
      default:         statusColor = Colors.orange;
    }

    String displayDate = attendanceDate;
    try {
      displayDate =
          DateFormat('dd MMM yyyy').format(DateTime.parse(attendanceDate));
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset:     const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:        Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.edit_calendar_rounded,
                      color: Colors.indigo.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayDate,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   14,
                            color:      Colors.black87),
                      ),
                      if (shiftName.isNotEmpty)
                        Text(shiftName,
                            style: TextStyle(
                                fontSize: 11,
                                color:    Colors.indigo.shade400)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color:        statusColor,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   11,
                        fontWeight: FontWeight.bold),
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
                    _infoChip(Icons.login_rounded,  'Start',
                        _fmtTimeStr(startTime), Colors.green),
                    const SizedBox(width: 8),
                    _infoChip(Icons.logout_rounded, 'End',
                        _fmtTimeStr(shiftEnd),  Colors.red),
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes_rounded,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(reason,
                            style: TextStyle(
                                fontSize: 12,
                                color:    Colors.grey.shade700)),
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
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
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

  Widget _infoChip(
      IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text(value,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText:   label,
      labelStyle:  TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon:  Icon(icon, color: Colors.indigo, size: 20),
      filled:      true,
      fillColor:   const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.indigo.shade400, width: 1.5)),
    );
  }

  // "HH:MM:SS" → "H:MM AM/PM"
  String _fmtHhmmss(String raw) {
    try {
      final parts  = raw.split(':');
      int   h      = int.parse(parts[0]);
      final m      = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h > 12) h -= 12;
      if (h == 0) h = 12;
      return '$h:$m $period';
    } catch (_) {
      return raw;
    }
  }

  // Handles both "HH:MM:SS" and full datetime strings from history
  String _fmtTimeStr(String raw) {
    if (raw.isEmpty) return 'N/A';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(raw).toLocal());
    } catch (_) {}
    return _fmtHhmmss(raw);
  }

  String _fmtCreatedAt(String raw) {
    try {
      return DateFormat('dd MMM, hh:mm a')
          .format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }
}
