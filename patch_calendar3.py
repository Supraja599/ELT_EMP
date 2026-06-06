with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Use the bytes before the comment line to insert calendar
old5 = (
    "            const SizedBox(height: 20),\n"
    "            // ── Quick-access cards"
)

# Find it
idx = content.find(old5)
if idx >= 0:
    print('Found at', idx)
    # Replace just the SizedBox before the comment
    insert_text = (
        "            const SizedBox(height: 16),\n"
        "            // Attendance calendar\n"
        "            _buildAttendanceCalendar(),\n"
        "            const SizedBox(height: 20),\n"
        "            // ── Quick-access cards"
    )
    content = content[:idx] + insert_text + content[idx + len(old5):]
    print('step5 done: calendar inserted')
else:
    print('step5 FAILED again')
    # print full context
    idx2 = content.find('Quick-access cards')
    if idx2 >= 0:
        print(repr(content[idx2-200:idx2+10]))

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
