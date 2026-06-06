import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/attendance_history_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Add _pickByCalendar method after _pickMonthYear ────────────────────────
# Find end of _pickMonthYear method
anchor = '  Color _statusColor(String status) {'
idx = content.find(anchor)
if idx < 0:
    print('anchor not found')
else:
    insert = """  /// Opens a full calendar so the user can jump to any month by picking a date.
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

"""
    content = content[:idx] + insert + content[idx:]
    print('step1 ok: _pickByCalendar added')

# ── 2. Add calendar icon button to AppBar actions ────────────────────────────
old2 = """        actions: [
          TextButton.icon(
            onPressed: _pickMonthYear,
            icon: const Icon(Icons.tune_rounded, color: Colors.teal, size: 18),
            label: Text(
              displayPeriod,
              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
            ),
          ),
        ],"""

new2 = """        actions: [
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
        ],"""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: calendar icon added to AppBar')
else:
    print('step2 FAILED')

with open('lib/attendance_history_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('attendance_history_screen.dart saved')
