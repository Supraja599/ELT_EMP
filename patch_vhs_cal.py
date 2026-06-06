import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Update _calStatusColor: WO → purple (visible on any day, not just Sunday)
old1 = """      case 'WO':   return Colors.red.shade100;
      default:     return isSunday ? Colors.red.shade100 : Colors.transparent;"""
new1 = """      case 'WO':   return Colors.purple.shade200;
      default:     return isSunday ? Colors.red.shade100 : Colors.transparent;"""
if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: WO color = purple')
else:
    print('step1 FAILED')

# ── 2. Replace itemBuilder: company-aware Sunday vs WO detection ──────────────
old2 = r"""                    itemBuilder: (_, i) {
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

new2 = r"""                    itemBuilder: (_, i) {
                      final dayNum = i - firstWeekday + 1;
                      if (dayNum <= 0 || dayNum > daysInMonth) {
                        return const SizedBox();
                      }
                      final isToday = now.year == _calYear &&
                          now.month == _calMonth &&
                          now.day == dayNum;
                      final isFuture = DateTime(
                        _calYear,
                        _calMonth,
                        dayNum,
                      ).isAfter(DateTime(now.year, now.month, now.day));
                      final code = _calData[dayNum];

                      // Company-aware Week Off / Sunday detection
                      // VHS (company 2): week off is any day the API marks WO
                      // Eltrive (others): column 0 = Sunday (auto-detected)
                      final isVHS = _companyId == '2';
                      final isWOByApi = code == 'WO';
                      final isEltriveSunday = !isVHS && (i % 7) == 0;
                      final showWSymbol = isWOByApi;
                      final showSSymbol = isEltriveSunday && !isWOByApi;

                      Color bg;
                      if (isFuture) {
                        bg = isEltriveSunday
                            ? Colors.red.shade50
                            : (isWOByApi ? Colors.purple.shade50 : Colors.transparent);
                      } else {
                        bg = _calStatusColor(code, isSunday: isEltriveSunday);
                      }

                      // Text colour based on background
                      final isLightBg = bg == Colors.red.shade100 ||
                          bg == Colors.red.shade50 ||
                          bg == Colors.yellow.shade700 ||
                          bg == Colors.purple.shade200 ||
                          bg == Colors.purple.shade50 ||
                          bg == Colors.transparent;
                      final textColor = isLightBg
                          ? (isEltriveSunday
                              ? Colors.red.shade600
                              : isWOByApi
                                  ? Colors.purple.shade700
                                  : Colors.black87)
                          : Colors.white;

                      // Which special symbol (W or S) to show below the day number
                      final symbol = showWSymbol ? 'W' : (showSSymbol ? 'S' : null);

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
                          child: symbol != null
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
                                      symbol,
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
    print('step2 ok: company-aware VHS WO vs Eltrive Sunday')
else:
    print('step2 FAILED')

# ── 3. Update legend to be company-aware (VHS: purple WO, Eltrive: red Sunday)
old3 = """                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.yellow.shade700, 'Half Day'),
                _calLegendDot(Colors.red.shade100, 'Sunday'),"""
new3 = r"""                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.yellow.shade700, 'Half Day'),
                if (_companyId == '2')
                  _calLegendDot(Colors.purple.shade200, 'Week Off (W)')
                else
                  _calLegendDot(Colors.red.shade100, 'Sunday (S)'),"""
if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: legend is company-aware')
else:
    print('step3 FAILED')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('check_in_out_screen.dart saved')
