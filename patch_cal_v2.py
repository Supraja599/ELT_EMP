import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Update _calStatusColor: WO→Sunday, OT/LT/LATE→Late, remove HD/H ──────
old1 = """  Color _calStatusColor(String? code) {
    switch (code) {
      case 'P':  return Colors.green.shade500;
      case 'A':  return Colors.red.shade400;
      case 'L':  return Colors.blue.shade400;
      case 'WO': return Colors.grey.shade400;
      case 'H':  return Colors.teal.shade400;
      case 'HD': return Colors.amber.shade600;
      case 'OT': return Colors.orange.shade400;
      default:   return Colors.transparent;
    }
  }"""

new1 = """  Color _calStatusColor(String? code, {bool isSunday = false}) {
    switch (code) {
      case 'P':    return Colors.green.shade500;
      case 'A':    return Colors.red.shade400;
      case 'L':    return Colors.blue.shade400;
      case 'OT':
      case 'LT':
      case 'LATE': return Colors.orange.shade500;
      case 'WO':   return Colors.blueGrey.shade200;
      default:     return isSunday ? Colors.blueGrey.shade200 : Colors.transparent;
    }
  }"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 done: _calStatusColor updated')
else:
    print('step1 FAILED')

# ── 2. Add _calSummaryItem helper after _calLegendDot ────────────────────────
old2 = """  Widget _buildAttendanceCalendar() {"""

new2 = """  Widget _calSummaryItem(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCalendar() {"""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 done: _calSummaryItem added')
else:
    print('step2 FAILED')

# ── 3. Add summary counts + Sunday detection + updated legend ─────────────────
# Replace the full _buildAttendanceCalendar body
# Find start of method body (after first line)
method_start = content.find('  Widget _buildAttendanceCalendar() {\n    final now = DateTime.now();')
if method_start < 0:
    print('step3 FAILED: method body not found')
else:
    # Find end of this method
    # Count braces from the return Container( to the closing }
    body_start = method_start
    # Find the end by looking for '  }\n\n  ///' or '  }\n\n  Widget _quickCard'
    end_markers = [
        '\n  /// Returns the correct logo',
        '\n  Widget _quickCard(',
        '\n  Widget _companyLogoWidget(',
    ]
    method_end = -1
    for m in end_markers:
        idx = content.find(m, body_start)
        if idx >= 0:
            if method_end < 0 or idx < method_end:
                method_end = idx

    if method_end < 0:
        print('step3 FAILED: method end not found')
    else:
        old_method = content[body_start:method_end]
        # Build the replacement
        new_method = r"""  Widget _buildAttendanceCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    // Dart weekday: 1=Mon..7=Sun; convert to 0=Sun..6=Sat
    final firstWeekday = firstDay.weekday == 7 ? 0 : firstDay.weekday;
    final monthName = DateFormat('MMMM yyyy').format(firstDay);
    final totalCells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;

    // Summary counts
    final presentCount = _calData.values.where((c) => c == 'P').length;
    final absentCount = _calData.values.where((c) => c == 'A').length;
    final leaveCount = _calData.values.where((c) => c == 'L').length;
    final lateCount = _calData.values
        .where((c) => c == 'OT' || c == 'LT' || c == 'LATE')
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month navigator
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: () {
                    _safeSetState(() {
                      if (_calMonth == 1) {
                        _calMonth = 12;
                        _calYear--;
                      } else {
                        _calMonth--;
                      }
                      _calData = {};
                    });
                    _fetchCalendarData();
                  },
                ),
                Text(
                  monthName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: () {
                    _safeSetState(() {
                      if (_calMonth == 12) {
                        _calMonth = 1;
                        _calYear++;
                      } else {
                        _calMonth++;
                      }
                      _calData = {};
                    });
                    _fetchCalendarData();
                  },
                ),
              ],
            ),
          ),
          // Summary count row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _calSummaryItem('Present', presentCount, Colors.green.shade500),
                const SizedBox(width: 6),
                _calSummaryItem('Absent', absentCount, Colors.red.shade400),
                const SizedBox(width: 6),
                _calSummaryItem('Leave', leaveCount, Colors.blue.shade400),
                const SizedBox(width: 6),
                _calSummaryItem('Late', lateCount, Colors.orange.shade500),
              ],
            ),
          ),
          const Divider(height: 10, thickness: 0.5),
          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                    ...[' Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                        .asMap()
                        .entries
                        .map(
                          (e) => Expanded(
                            child: Center(
                              child: Text(
                                e.value.trim(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: e.key == 0
                                      ? Colors.blueGrey.shade400
                                      : Colors.black45,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
            ),
          ),
          const SizedBox(height: 4),
          // Calendar grid
          _calLoading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 2,
                      childAspectRatio: 1,
                    ),
                    itemCount: totalCells,
                    itemBuilder: (_, i) {
                      final dayNum = i - firstWeekday + 1;
                      if (dayNum <= 0 || dayNum > daysInMonth) {
                        return const SizedBox();
                      }
                      // Column 0 = Sunday
                      final isSunday = (i % 7) == 0;
                      final isToday = now.year == _calYear &&
                          now.month == _calMonth &&
                          now.day == dayNum;
                      final isFuture = DateTime(
                        _calYear,
                        _calMonth,
                        dayNum,
                      ).isAfter(DateTime(now.year, now.month, now.day));
                      final code = _calData[dayNum];
                      Color bg;
                      if (isFuture) {
                        bg = isSunday
                            ? Colors.blueGrey.shade50
                            : Colors.transparent;
                      } else {
                        bg = _calStatusColor(code, isSunday: isSunday);
                      }
                      final isColoured = bg != Colors.transparent &&
                          bg != Colors.blueGrey.shade50;
                      return Container(
                        decoration: BoxDecoration(
                          color: bg,
                          shape: BoxShape.circle,
                          border: isToday
                              ? Border.all(
                                  color: Colors.teal.shade700,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isColoured
                                  ? Colors.white
                                  : (isSunday
                                      ? Colors.blueGrey.shade400
                                      : Colors.black54),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _calLegendDot(Colors.green.shade500, 'Present'),
                _calLegendDot(Colors.red.shade400, 'Absent'),
                _calLegendDot(Colors.blue.shade400, 'Leave'),
                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.blueGrey.shade200, 'Sunday'),
              ],
            ),
          ),
        ],
      ),
    );
  }"""

        content = content[:body_start] + new_method + content[method_end:]
        print('step3 done: full calendar method replaced')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
