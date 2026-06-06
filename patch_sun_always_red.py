import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Sunday always shows S (ignore WO/Holiday status for Eltrive Sundays) ──
old1 = """                      final showWSymbol = isWOByApi;
                      final showHSymbol = isHoliday;
                      final showSSymbol = isEltriveSunday && !isWOByApi && !isHoliday;"""
new1 = """                      final showWSymbol = isWOByApi && !isEltriveSunday; // VHS WO only
                      final showHSymbol = isHoliday && !isEltriveSunday;        // Holiday on non-Sunday
                      final showSSymbol = isEltriveSunday;                       // Sunday ALWAYS S"""
if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: Sunday always shows S')
else:
    print('step1 FAILED')

# ── 2. Sunday ALWAYS gets light-red bg regardless of API status code ──────────
old2 = """                      } else {
                        bg = _calStatusColor(code, isSunday: isEltriveSunday);
                      }"""
new2 = """                      } else if (isEltriveSunday) {
                        // Sunday is ALWAYS light-red — ignore API status (P/A/etc.)
                        bg = Colors.red.shade100;
                      } else {
                        bg = _calStatusColor(code, isSunday: false);
                      }"""
if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: Sunday bg always red.shade100')
else:
    print('step2 FAILED')

# ── 3. Fix textColor: for Sunday (light-red bg) always use red text ───────────
old3 = """                      final isLightBg = bg == Colors.red.shade100 ||
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
new3 = """                      // Text colour: dark on light bg, white on dark bg
                      Color textColor;
                      if (isEltriveSunday) {
                        textColor = Colors.red.shade700;
                      } else if (isWOByApi) {
                        textColor = Colors.purple.shade700;
                      } else if (isHoliday || bg == Colors.red.shade100) {
                        textColor = Colors.red.shade700;
                      } else if (bg == Colors.yellow.shade700 ||
                          bg == Colors.orange.shade400 ||
                          bg == Colors.transparent) {
                        textColor = Colors.black87;
                      } else {
                        textColor = Colors.white; // dark bg: green, red, blue, orange
                      }"""
if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: textColor updated')
else:
    print('step3 FAILED')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
