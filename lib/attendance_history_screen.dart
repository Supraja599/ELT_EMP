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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
      case 'O':  return 'Holiday';
      case 'H':
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

        // Auto-scroll to highlighted record after build
        if (_highlightedDay != null) {
          final idx = parsed.indexWhere((r) => r['day_num'] == _highlightedDay);
          if (idx >= 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // ~90 (summary row) + 16 (top padding) + 48 (table header) + idx * 44 (row height)
              final offset = 170.0 + idx * 44.0;
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  offset,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                );
              }
            });
          }
        }
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

  /// Opens a full calendar so the user can jump to any month by picking a date.
  Future<void> _pickByCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_selectedYear, _selectedMonth, 1),
      firstDate: DateTime(2020, 1),
      lastDate: DateTime.now(),
      helpText: 'Pick a month to view',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.teal),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = picked.month;
        _selectedYear  = picked.year;
        _highlightedDay = null;
      });
      _fetchHistory();
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':                        return Colors.green;
      case 'late':                           return Colors.orange.shade500;
      case 'absent':                         return Colors.red;
      case 'half day': case 'half-day':
      case 'comp off': case 'compoff':       return Colors.orange.shade400;
      case 'leave':                          return Colors.yellow.shade700;
      case 'ot': case 'overtime':            return Colors.orange.shade500;
      case 'holiday':                        return Colors.red.shade300;
      case 'weekly off': case 'weekoff':     return Colors.purple.shade300;
      default:                               return Colors.grey;
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
          // Calendar picker — pick any date to jump to that month
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.teal),
            tooltip: 'Pick by calendar',
            onPressed: _pickByCalendar,
          ),
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
                    controller: _scrollController,
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

                      // ── Records Table ───────────────────────────────────────
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
                        _buildRecordsTable(),
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

  Widget _buildRecordsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF00695C), // teal.shade700
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                _AhCell(text: 'Date',    isHeader: true, flex: 3),
                _AhCell(text: 'In',      isHeader: true, flex: 2),
                _AhCell(text: 'Out',     isHeader: true, flex: 2),
                _AhCell(text: 'Hours',   isHeader: true, flex: 2),
                _AhCell(text: 'Status',  isHeader: true, flex: 3),
              ],
            ),
          ),
          // Rows
          ...List.generate(_records.length, (i) {
            final r = _records[i];
            final date      = r['date']?.toString() ?? '';
            final checkIn   = r['check_in_time']?.toString() ?? '--:--';
            final checkOut  = r['check_out_time']?.toString() ?? '--:--';
            final hours     = r['total_hours']?.toString() ?? '--';
            final status    = r['status']?.toString() ?? '';
            final dayNum    = r['day_num'] as int? ?? 0;
            final isHighlighted = _highlightedDay != null && dayNum == _highlightedDay;
            final statusColor   = _statusColor(status);

            String dayStr = '';
            try {
              final dt = DateTime.parse(date);
              dayStr = DateFormat('dd MMM').format(dt);
            } catch (_) { dayStr = date; }

            Color rowColor;
            if (isHighlighted) {
              rowColor = Colors.teal.shade50;
            } else {
              rowColor = i % 2 == 0 ? Colors.grey.shade50 : Colors.white;
            }

            return Container(
              decoration: BoxDecoration(
                color: rowColor,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                  left: isHighlighted
                      ? BorderSide(color: Colors.teal.shade600, width: 3)
                      : BorderSide.none,
                ),
                borderRadius: i == _records.length - 1
                    ? const BorderRadius.vertical(bottom: Radius.circular(16))
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  _AhCell(text: dayStr,   flex: 3),
                  _AhCell(text: checkIn,  flex: 2),
                  _AhCell(text: checkOut, flex: 2),
                  _AhCell(text: hours,    flex: 2),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AhCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final int flex;

  const _AhCell({required this.text, this.isHeader = false, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: isHeader ? 11 : 11,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
