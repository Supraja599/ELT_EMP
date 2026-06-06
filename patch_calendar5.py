with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the SizedBox(height: 20) right before the Quick-access cards section
# Use "Attendance History: all companies" as anchor
anchor = '            // Attendance History: all companies'
idx = content.find(anchor)
print('anchor found at:', idx)

if idx >= 0:
    # Look backward from anchor to find the SizedBox(height: 20),\n  line
    segment_before = content[:idx]
    # Find the last occurrence of SizedBox(height: 20), before this anchor
    sz_idx = segment_before.rfind('            const SizedBox(height: 20),\n')
    print('SizedBox(20) found at:', sz_idx)
    if sz_idx >= 0:
        insert_pos = sz_idx  # insert before this SizedBox
        insert_text = (
            "            // Attendance calendar\n"
            "            _buildAttendanceCalendar(),\n"
            "            const SizedBox(height: 16),\n"
        )
        content = content[:insert_pos] + insert_text + content[insert_pos:]
        print('step5 done: calendar inserted at', insert_pos)

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('saved')
