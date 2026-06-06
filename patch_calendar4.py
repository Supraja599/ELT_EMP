with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find location by unique context: "Attendance History" card
idx_ah = content.find("'Attendance\\nHistory'")
if idx_ah < 0:
    idx_ah = content.find("label: 'Attendance")
print('Attendance History found at:', idx_ah)

# Find the Quick-access cards comment just before it
idx_comment = content.rfind('// ', 0, idx_ah)
print('last // before AH:', idx_comment)
print(repr(content[idx_comment-100:idx_comment+50]))
