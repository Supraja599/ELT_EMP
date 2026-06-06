import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ─────────────────────────────────────────────────────────────────────────────
# 1. Fix status bar overlap: wrap the return Column in SafeArea
# ─────────────────────────────────────────────────────────────────────────────
old1 = """        return Column(
          children: [
            // Fixed header — stays visible while body scrolls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 68,"""
new1 = """        return SafeArea(
          bottom: false,
          child: Column(
          children: [
            // Fixed header — stays visible while body scrolls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 68,"""
if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: SafeArea wraps header')
else:
    print('step1 FAILED')

# Also fix the closing of the Column → Column + SafeArea
old1b = """          ],
        );
      }
      switch (index) {"""
new1b = """          ],
          ),
        );
      }
      switch (index) {"""
if old1b in content:
    content = content.replace(old1b, new1b, 1)
    print('step1b ok: SafeArea closing fixed')
else:
    print('step1b FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 2. Update _calStatusColor:
#    Leave (L) → Yellow   |  Half Day (HD) → Orange  |  Comp Off (CO) → Orange
#    Holiday (H) → light-red (same bg as Sunday, shows 'H' letter)
# ─────────────────────────────────────────────────────────────────────────────
old2 = """  Color _calStatusColor(String? code, {bool isSunday = false}) {
    switch (code) {
      case 'P':    return Colors.green.shade500;
      case 'A':    return Colors.red.shade400;
      case 'L':    return Colors.blue.shade400;
      case 'OT':
      case 'LT':
      case 'LATE': return Colors.orange.shade500;
      case 'HD':   return Colors.yellow.shade700;
      case 'WO':   return Colors.purple.shade200;
      default:     return isSunday ? Colors.red.shade100 : Colors.transparent;
    }
  }"""
new2 = """  Color _calStatusColor(String? code, {bool isSunday = false}) {
    switch (code) {
      case 'P':    return Colors.green.shade500;
      case 'A':    return Colors.red.shade400;
      case 'L':    return Colors.yellow.shade700;   // Leave = yellow
      case 'OT':
      case 'LT':
      case 'LATE': return Colors.orange.shade500;   // Late/OT = orange
      case 'HD':
      case 'CO':
      case 'COMPOFF': return Colors.orange.shade400; // Half Day / Comp Off = orange
      case 'H':    return Colors.red.shade100;       // Holiday = same bg as Sunday
      case 'WO':   return Colors.purple.shade200;
      default:     return isSunday ? Colors.red.shade100 : Colors.transparent;
    }
  }"""
if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: colors updated')
else:
    print('step2 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 3. In itemBuilder: Holiday (H) also shows a letter "H" like Sunday shows "S"
# ─────────────────────────────────────────────────────────────────────────────
old3 = """                      final isVHS = _companyId == '2';
                      final isWOByApi = code == 'WO';
                      final isEltriveSunday = !isVHS && (i % 7) == 0;
                      final showWSymbol = isWOByApi;
                      final showSSymbol = isEltriveSunday && !isWOByApi;"""
new3 = """                      final isVHS = _companyId == '2';
                      final isWOByApi = code == 'WO';
                      final isHoliday = code == 'H';
                      final isEltriveSunday = !isVHS && (i % 7) == 0;
                      final showWSymbol = isWOByApi;
                      final showHSymbol = isHoliday;
                      final showSSymbol = isEltriveSunday && !isWOByApi && !isHoliday;"""
if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: holiday detection added')
else:
    print('step3 FAILED')

old3b = """                      // Which special symbol (W or S) to show below the day number
                      final symbol = showWSymbol ? 'W' : (showSSymbol ? 'S' : null);"""
new3b = """                      // Symbol to show: W=WeekOff, H=Holiday, S=Sunday, else null
                      final symbol = showWSymbol ? 'W' : (showHSymbol ? 'H' : (showSSymbol ? 'S' : null));"""
if old3b in content:
    content = content.replace(old3b, new3b, 1)
    print('step3b ok: H symbol wired')
else:
    print('step3b FAILED')

# Update bg logic: holiday future also shows light red
old3c = """                      Color bg;
                      if (isFuture) {
                        bg = isEltriveSunday
                            ? Colors.red.shade50
                            : (isWOByApi ? Colors.purple.shade50 : Colors.transparent);
                      } else {
                        bg = _calStatusColor(code, isSunday: isEltriveSunday);
                      }"""
new3c = """                      Color bg;
                      if (isFuture) {
                        bg = isEltriveSunday
                            ? Colors.red.shade50
                            : isWOByApi
                                ? Colors.purple.shade50
                                : isHoliday
                                    ? Colors.red.shade50
                                    : Colors.transparent;
                      } else {
                        bg = _calStatusColor(code, isSunday: isEltriveSunday);
                      }"""
if old3c in content:
    content = content.replace(old3c, new3c, 1)
    print('step3c ok: holiday future bg')
else:
    print('step3c FAILED')

# Update isLightBg to include holiday
old3d = """                      final isLightBg = bg == Colors.red.shade100 ||
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
                          : Colors.white;"""
new3d = """                      final isLightBg = bg == Colors.red.shade100 ||
                          bg == Colors.red.shade50 ||
                          bg == Colors.yellow.shade700 ||
                          bg == Colors.orange.shade400 ||
                          bg == Colors.purple.shade200 ||
                          bg == Colors.purple.shade50 ||
                          bg == Colors.transparent;
                      final textColor = isLightBg
                          ? (isEltriveSunday || isHoliday
                              ? Colors.red.shade700
                              : isWOByApi
                                  ? Colors.purple.shade700
                                  : Colors.black87)
                          : Colors.white;"""
if old3d in content:
    content = content.replace(old3d, new3d, 1)
    print('step3d ok: textColor for holiday')
else:
    print('step3d FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 4. Update summary row: Leave color = yellow
# ─────────────────────────────────────────────────────────────────────────────
old4 = "_calSummaryItem('Leave', leaveCount, Colors.blue.shade400),"
new4 = "_calSummaryItem('Leave', leaveCount, Colors.yellow.shade700),"
if old4 in content:
    content = content.replace(old4, new4, 1)
    print('step4 ok: summary Leave = yellow')
else:
    print('step4 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 5. Update legend: Leave=yellow, HalfDay+CompOff=orange, Holiday like Sunday
# ─────────────────────────────────────────────────────────────────────────────
old5 = """                _calLegendDot(Colors.green.shade500, 'Present'),
                _calLegendDot(Colors.red.shade400, 'Absent'),
                _calLegendDot(Colors.blue.shade400, 'Leave'),
                _calLegendDot(Colors.orange.shade500, 'Late'),
                _calLegendDot(Colors.yellow.shade700, 'Half Day'),
                if (_companyId == '2')
                  _calLegendDot(Colors.purple.shade200, 'Week Off (W)')
                else
                  _calLegendDot(Colors.red.shade100, 'Sunday (S)'),"""
new5 = """                _calLegendDot(Colors.green.shade500, 'Present'),
                _calLegendDot(Colors.red.shade400, 'Absent'),
                _calLegendDot(Colors.yellow.shade700, 'Leave'),
                _calLegendDot(Colors.orange.shade500, 'Late / OT'),
                _calLegendDot(Colors.orange.shade400, 'Half Day / CO'),
                _calLegendDot(Colors.red.shade100, 'Holiday (H)'),
                if (_companyId == '2')
                  _calLegendDot(Colors.purple.shade200, 'Week Off (W)')
                else
                  _calLegendDot(Colors.red.shade100, 'Sunday (S)'),"""
if old5 in content:
    content = content.replace(old5, new5, 1)
    print('step5 ok: legend updated')
else:
    print('step5 FAILED')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('check_in_out_screen.dart saved')

# ─────────────────────────────────────────────────────────────────────────────
# 6. Also update attendance_history_screen.dart status colours for consistency
# ─────────────────────────────────────────────────────────────────────────────
with open('lib/attendance_history_screen.dart', 'r', encoding='utf-8') as f:
    hist = f.read()

old6 = """  Color _statusColor(String status) {
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
  }"""
new6 = """  Color _statusColor(String status) {
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
  }"""
if old6 in hist:
    hist = hist.replace(old6, new6, 1)
    print('step6 ok: history screen colors synced')
else:
    print('step6 FAILED')

with open('lib/attendance_history_screen.dart', 'w', encoding='utf-8') as f:
    f.write(hist)
print('attendance_history_screen.dart saved')
