with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 4. Remove the live clock (currentTime) widget
old4 = """            const SizedBox(height: 20),
            Text(
              currentTime,
              style: const TextStyle(
                fontSize: 34,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              today,
              style: const TextStyle(fontSize: 18, color: Colors.black54),
            ),
            const SizedBox(height: 30),"""

new4 = """            const SizedBox(height: 8),
            Text(
              today,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 16),"""

if old4 in content:
    content = content.replace(old4, new4, 1)
    print('step4 done: clock removed')
else:
    print('step4 FAILED')
    # Try to find partial
    if 'currentTime,' in content:
        idx = content.index('currentTime,')
        print('Found currentTime at index', idx)
        print(repr(content[idx-200:idx+200]))

# 5. Add calendar after "Shifts Working Time" line and before quick-access cards
old5 = """            const SizedBox(height: 20),
            // ── Quick-access cards ─────────────────────────────────────────"""

new5 = """            const SizedBox(height: 16),
            // Attendance calendar
            _buildAttendanceCalendar(),
            const SizedBox(height: 20),
            // ── Quick-access cards ─────────────────────────────────────────"""

if old5 in content:
    content = content.replace(old5, new5, 1)
    print('step5 done: calendar added to body')
else:
    print('step5 FAILED, trying alternate pattern...')
    # Try without the line drawing chars
    idx = content.find('Quick-access cards')
    if idx >= 0:
        print('Found "Quick-access cards" at', idx)
        print(repr(content[idx-150:idx+50]))
    else:
        print('Quick-access cards not found either')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
