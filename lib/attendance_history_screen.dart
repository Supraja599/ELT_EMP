import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String empId;
  final String authToken;
  final String empName;
  final DateTime? initialDate;

  const AttendanceHistoryScreen({
    super.key,
    required this.empId,
    required this.authToken,
    required this.empName,
    this.initialDate,
  });

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = false;
  String _error = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _highlightedDay;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedMonth = widget.initialDate!.month;
      _selectedYear  = widget.initialDate!.year;
      _highlightedDay = widget.initialDate!.day;
    }
    _fetchHistory();
  }

  // Maps single-letter status codes from the API to display names
  String _statusCodeToLabel(String code) {
    switch (code.toUpperCase()) {
      case 'P':  return 'Present';
      case 'A':  return 'Absent';
      case 'L':  return 'Leave';
      case 'WO': return 'Weekly Off';
      case 'H':  return 'Holiday';
      case 'HD': return 'Half Day';
      case 'OT': return 'Overtime';
      default:   return code;
    }
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await ApiService.fetchAttendanceHistory(
        authToken: widget.authToken,
        month: _selectedMonth,
        year: _selectedYear,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        // Response format: { days: { day1: {...}, day2: {...}, ... } }
        final daysMap = data['days'] as Map<String, dynamic>? ?? {};
        final int month = data['month'] ?? _selectedMonth;
        final int year = data['year'] ?? _selectedYear;

        final List<Map<String, dynamic>> parsed = [];
        daysMap.forEach((key, value) {
          // key is "day1", "day2", ...
          final dayNum = int.tryParse(key.replaceAll('day', '')) ?? 0;
          if (dayNum == 0) return;

          final statusCode = (value['status'] ?? 'A').toString();
          parsed.add({
            'date': DateTime(year, month, dayNum).toIso8601String().split('T')[0],
            'status': _statusCodeToLabel(statusCode),
            'check_in_time': value['checkin']?.toString() ?? '--:--',
            'check_out_time': value['checkout']?.toString() ?? '--:--',
            'total_hours': value['duration']?.toString() ?? '--',
            'day_num': dayNum,
          });
        });

        // Sort by day number
        parsed.sort((a, b) => (a['day_num'] as int).compareTo(b['day_num'] as int));

        setState(() => _records = parsed);
      } else {
        setState(() => _error = data['message'] ?? 'Failed to fetch attendance');
      }
    } catch (e) {
      setState(() => _error = 'Could not load attendance. Check your connection.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickMonthYear() async {
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear;

    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final years = List.generate(4, (i) => DateTime.now().year - 1 + i);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.teal),
                  const SizedBox(width: 8),
                  const Text('Select Period', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              // Month chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(12, (i) {
                  final isSelected = tempMonth == i + 1;
                  return ChoiceChip(
                    label: Text(monthNames[i]),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setLocal(() => tempMonth = i + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              // Year chips
              Wrap(
                spacing: 8,
                children: years.map((y) {
                  final isSelected = tempYear == y;
                  return ChoiceChip(
                    label: Text('$y'),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setLocal(() => tempYear = y),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedMonth = tempMonth;
                      _selectedYear = tempYear;
                    });
                    _fetchHistory();
                  },
                  child: const Text('Show Attendance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present': return Colors.green;
      case 'late': return Colors.orange;
      case 'absent': return Colors.red;
      case 'half day': case 'half-day': return Colors.amber.shade700;
      case 'leave': return Colors.blue;
      case 'ot': case 'overtime': return Colors.purple;
      case 'holiday': return Colors.teal;
      case 'weekly off': case 'weekoff': return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'present': return Icons.check_circle_rounded;
      case 'late': return Icons.schedule_rounded;
      case 'absent': return Icons.cancel_rounded;
      case 'half day': case 'half-day': return Icons.timelapse_rounded;
      case 'leave': return Icons.beach_access_rounded;
      case 'ot': case 'overtime': return Icons.star_rounded;
      case 'holiday': return Icons.celebration_rounded;
      case 'weekly off': case 'weekoff': return Icons.weekend_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Map<String, int> _getSummary() {
    final counts = <String, int>{'present': 0, 'late': 0, 'absent': 0, 'leave': 0};
    for (final r in _records) {
      final s = (r['status'] ?? '').toString().toLowerCase();
      if (s == 'present') {
        counts['present'] = (counts['present'] ?? 0) + 1;
      } else if (s == 'late') {
        counts['late'] = (counts['late'] ?? 0) + 1;
        counts['present'] = (counts['present'] ?? 0) + 1;
      } else if (s == 'absent') {
        counts['absent'] = (counts['absent'] ?? 0) + 1;
      } else if (s == 'leave') {
        counts['leave'] = (counts['leave'] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final monthNames = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final displayPeriod = '${monthNames[_selectedMonth]} $_selectedYear';
    final summary = _getSummary();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Attendance History',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton.icon(
            onPressed: _pickMonthYear,
            icon: const Icon(Icons.tune_rounded, color: Colors.teal, size: 18),
            label: Text(
              displayPeriod,
              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 72, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 15)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchHistory,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Summary Cards ───────────────────────────────────────
                      Row(
                        children: [
                          _summaryTile('Present', summary['present'] ?? 0, const Color(0xFF2E7D32)),
                          const SizedBox(width: 8),
                          _summaryTile('Late', summary['late'] ?? 0, const Color(0xFFE65100)),
                          const SizedBox(width: 8),
                          _summaryTile('Absent', summary['absent'] ?? 0, const Color(0xFFC62828)),
                          const SizedBox(width: 8),
                          _summaryTile('Leave', summary['leave'] ?? 0, const Color(0xFF1565C0)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Records ─────────────────────────────────────────────
                      if (_records.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Column(
                            children: [
                              const Icon(Icons.event_busy_rounded, size: 72, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                'No records for $displayPeriod',
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._records.map(_buildRecordCard),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryTile(String label, int count, Color color) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              // Coloured accent bar at top
              Container(height: 4, color: color),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final date = record['date']?.toString() ?? '';
    final checkIn = record['check_in_time']?.toString()
        ?? record['checkin_time']?.toString()
        ?? '--:--';
    final checkOut = record['check_out_time']?.toString()
        ?? record['checkout_time']?.toString()
        ?? '--:--';
    final totalHours = record['total_hours']?.toString()
        ?? record['working_hours']?.toString()
        ?? '--:--';
    final status = record['status']?.toString() ?? 'Present';
    final shiftName = record['shift_name']?.toString() ?? '';
    final isLate = record['is_late'] == true || record['is_late'] == 1;
    final isEarlyOut = record['is_early_checkout'] == true || record['is_early_checkout'] == 1;
    final otHours = record['ot_hours']?.toString() ?? '';

    DateTime? parsedDate;
    try { parsedDate = DateTime.parse(date); } catch (_) {}
    final displayDate = parsedDate != null
        ? DateFormat('EEE, dd MMM yyyy').format(parsedDate)
        : date;

    final dayNum = record['day_num'] as int? ?? 0;
    final isHighlighted = _highlightedDay != null && dayNum == _highlightedDay;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? Colors.teal.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isHighlighted
            ? Border.all(color: Colors.teal.shade400, width: 2)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_statusIcon(status), color: _statusColor(status), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (shiftName.isNotEmpty)
                        Text(shiftName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _timeChip(Icons.login_rounded, checkIn, Colors.green),
                const SizedBox(width: 12),
                _timeChip(Icons.logout_rounded, checkOut, Colors.red),
                const SizedBox(width: 12),
                _timeChip(Icons.timer_rounded, totalHours, Colors.blue),
              ],
            ),
            // Flags row
            if (isLate || isEarlyOut || otHours.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  if (isLate)
                    _flagChip('Late Check-in', Colors.orange),
                  if (isEarlyOut)
                    _flagChip('Early Check-out', Colors.deepOrange),
                  if (otHours.isNotEmpty)
                    _flagChip('OT: $otHours', Colors.purple),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _flagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
