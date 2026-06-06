import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()
start = content.find('          // Legend')
end = content.find('\n  Widget _quickCard(')
print(content[start:end])
