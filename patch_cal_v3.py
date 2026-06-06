import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ─────────────────────────────────────────────────────────────────────────────
# 1. Update _calStatusColor: Sunday=light-red, HalfDay=yellow
# ─────────────────────────────────────────────────────────────────────────────
old1 = """  Color _calStatusColor(String? code, {bool isSunday = false}) {
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

new1 = """  Color _calStatusColor(String? code, {bool isSunday = false}) {
    switch (code) {
      case 'P':    return Colors.green.shade500;
      case 'A':    return Colors.red.shade400;
      case 'L':    return Colors.blue.shade400;
      case 'OT':
      case 'LT':
      case 'LATE': return Colors.orange.shade500;
      case 'HD':   return Colors.yellow.shade700;
      case 'WO':   return Colors.red.shade100;
      default:     return isSunday ? Colors.red.shade100 : Colors.transparent;
    }
  }"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: colors updated')
else:
    print('step1 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 2. Replace calendar grid itemBuilder: bold numbers, Sunday shows "S",
#    tap navigates to AttendanceHistoryScreen with that date highlighted
# ─────────────────────────────────────────────────────────────────────────────
old2 = """                    itemBuilder: (_, i) {
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
                    },"""

new2 = r"""                    itemBuilder: (_, i) {
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
                            ? Colors.red.shade50
                            : Colors.transparent;
                      } else {
                        bg = _calStatusColor(code, isSunday: isSunday);
                      }
                      final hasStatus = !isFuture && code != null && code.isNotEmpty;
                      final isDarkBg = hasStatus &&
                          bg != Colors.red.shade100 &&
                          bg != Colors.yellow.shade700 &&
                          bg != Colors.red.shade50;
                      final textColor = isDarkBg
                          ? Colors.white
                          : (isSunday
                              ? Colors.red.shade600
                              : Colors.black87);

                      return GestureDetector(
                        onTap: isFuture
                            ? null
                            : () {
                                final tappedDate = DateTime(_calYear, _calMonth, dayNum);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AttendanceHistoryScreen(
                                      empId: widget.empId,
                                      authToken: widget.authToken,
                                      empName: widget.empName,
                                      initialDate: tappedDate,
                                    ),
                                  ),
                                );
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            color: bg,
                            shape: BoxShape.circle,
                            border: isToday
                                ? Border.all(color: Colors.teal.shade700, width: 2)
                                : null,
                          ),
                          child: isSunday
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      'S',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        height: 0.9,
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },"""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: calendar grid updated (bold, Sunday S, tap nav)')
else:
    print('step2 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 3. Update legend: Sunday=light-red, HalfDay=yellow
# ─────────────────────────────────────────────────────────────────────────────
old3 = """                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.blueGrey.shade200, 'Sunday'),"""

new3 = """                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.yellow.shade700, 'Half Day'),
                _calLegendDot(Colors.red.shade100, 'Sunday'),"""

if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: legend updated')
else:
    print('step3 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 4. Update summary legend in _buildAttendanceCalendar: future Sunday color
# ─────────────────────────────────────────────────────────────────────────────
old4 = "                _calLegendDot(Colors.grey.shade400, 'Week Off'),"
new4 = ""  # remove Week Off from legend since Sunday covers it
if old4 in content:
    content = content.replace(old4, new4, 1)
    print('step4 ok: removed Week Off from legend')
else:
    print('step4 FAILED (may not exist)')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('calendar v3 patches saved')
