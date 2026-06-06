with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 3. Add _fetchCalendarData and helper methods after _loadCompanyLogo
old3 = '''  Future<void> _loadCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final logo     = prefs.getString("companyLogo") ?? "";
    final cId      = prefs.getString("companyId")   ?? "";
    if (mounted) {
      _safeSetState(() {
        _companyLogoUrl = logo;
        _companyId      = cId;
      });
    }
  }'''

new3 = old3 + r"""

  Future<void> _fetchCalendarData() async {
    _safeSetState(() => _calLoading = true);
    try {
      final response = await ApiService.fetchAttendanceHistory(
        authToken: widget.authToken,
        month: _calMonth,
        year: _calYear,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final daysMap = data['days'] as Map<String, dynamic>? ?? {};
        final Map<int, String> result = {};
        daysMap.forEach((key, value) {
          final dayNum = int.tryParse(key.replaceAll('day', '')) ?? 0;
          if (dayNum > 0) result[dayNum] = (value['status'] ?? 'A').toString().toUpperCase();
        });
        _safeSetState(() => _calData = result);
      }
    } catch (_) {}
    _safeSetState(() => _calLoading = false);
  }

  Color _calStatusColor(String? code) {
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
  }

  Widget _calLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

  Widget _buildAttendanceCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    // Dart weekday: 1=Mon..7=Sun; convert to 0=Sun..6=Sat
    final firstWeekday = firstDay.weekday == 7 ? 0 : firstDay.weekday;
    final monthName = DateFormat('MMMM yyyy').format(firstDay);
    final totalCells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;

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
          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
                      final isToday = now.year == _calYear &&
                          now.month == _calMonth &&
                          now.day == dayNum;
                      final isFuture = DateTime(
                        _calYear,
                        _calMonth,
                        dayNum,
                      ).isAfter(DateTime(now.year, now.month, now.day));
                      final code = _calData[dayNum];
                      final bg =
                          isFuture ? Colors.transparent : _calStatusColor(code);
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
                              color: bg == Colors.transparent
                                  ? Colors.black54
                                  : Colors.white,
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
                _calLegendDot(Colors.amber.shade600, 'Half Day'),
                _calLegendDot(Colors.grey.shade400, 'Week Off'),
                _calLegendDot(Colors.teal.shade400, 'Holiday'),
              ],
            ),
          ),
        ],
      ),
    );
  }"""

if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 done: _buildAttendanceCalendar added')
else:
    print('step3 FAILED: pattern not found')
    print('searching for partial match...')
    if '_loadCompanyLogo' in content:
        print('  _loadCompanyLogo found')
    else:
        print('  _loadCompanyLogo NOT found')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
