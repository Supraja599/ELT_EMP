import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/attendance_history_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Add initialDate param to widget ──────────────────────────────────────
old1 = """class AttendanceHistoryScreen extends StatefulWidget {
  final String empId;
  final String authToken;
  final String empName;

  const AttendanceHistoryScreen({
    super.key,
    required this.empId,
    required this.authToken,
    required this.empName,
  });"""

new1 = """class AttendanceHistoryScreen extends StatefulWidget {
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
  });"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: initialDate param added')
else:
    print('step1 FAILED')

# ── 2. Use initialDate in initState + add _highlightedDay ────────────────────
old2 = """  List<Map<String, dynamic>> _records = [];
  bool _isLoading = false;
  String _error = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }"""

new2 = """  List<Map<String, dynamic>> _records = [];
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
  }"""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: initState uses initialDate')
else:
    print('step2 FAILED')

# ── 3. Highlight the matching record card ────────────────────────────────────
old3 = """  Widget _buildRecordCard(Map<String, dynamic> record) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),"""

new3 = """  Widget _buildRecordCard(Map<String, dynamic> record) {
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
      ),"""

if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: record card highlight added')
else:
    print('step3 FAILED')

# ── 4. Fix AppBar title (remove "- Patched!" test label) ────────────────────
old4 = "          'Attendance History - Patched!',"
new4 = "          'Attendance History',"
if old4 in content:
    content = content.replace(old4, new4, 1)
    print('step4 ok: appbar title fixed')
else:
    print('step4: title already clean')

with open('lib/attendance_history_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('attendance_history_screen.dart saved')
