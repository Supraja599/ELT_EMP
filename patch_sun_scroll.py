import sys
sys.stdout.reconfigure(encoding='utf-8')

# ── check_in_out_screen.dart: Sunday/WO shows ONLY the letter, no number ─────
with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old1 = """                          child: symbol != null
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
                                ),"""

new1 = r"""                          child: symbol != null
                              // Sunday or Week-Off: show only the letter (S or W)
                              ? Center(
                                  child: Text(
                                    symbol,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
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
                                ),"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: Sunday/WO shows only letter')
else:
    print('step1 FAILED')

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

# ── attendance_history_screen.dart: auto-scroll + brighter highlight ──────────
with open('lib/attendance_history_screen.dart', 'r', encoding='utf-8') as f:
    hist = f.read()

# 2a. Add ScrollController to state variables
old2a = """  List<Map<String, dynamic>> _records = [];
  bool _isLoading = false;
  String _error = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _highlightedDay;"""
new2a = """  List<Map<String, dynamic>> _records = [];
  bool _isLoading = false;
  String _error = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _highlightedDay;
  final ScrollController _scrollController = ScrollController();"""
if old2a in hist:
    hist = hist.replace(old2a, new2a, 1)
    print('step2a ok: ScrollController added')
else:
    print('step2a FAILED')

# 2b. Dispose the controller
old2b = """  @override
  void initState() {
    super.initState();"""
new2b = """  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();"""
if old2b in hist:
    hist = hist.replace(old2b, new2b, 1)
    print('step2b ok: dispose added')
else:
    print('step2b FAILED')

# 2c. After fetching, scroll to highlighted record
old2c = """        // Sort by day number
        parsed.sort((a, b) => (a['day_num'] as int).compareTo(b['day_num'] as int));

        setState(() => _records = parsed);"""
new2c = """        // Sort by day number
        parsed.sort((a, b) => (a['day_num'] as int).compareTo(b['day_num'] as int));

        setState(() => _records = parsed);

        // Auto-scroll to highlighted record after build
        if (_highlightedDay != null) {
          final idx = parsed.indexWhere((r) => r['day_num'] == _highlightedDay);
          if (idx >= 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // ~90 (summary row) + 16 (top padding) + idx * 110 (card + margin)
              final offset = 106.0 + idx * 110.0;
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  offset,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                );
              }
            });
          }
        }"""
if old2c in hist:
    hist = hist.replace(old2c, new2c, 1)
    print('step2c ok: auto-scroll after fetch')
else:
    print('step2c FAILED')

# 2d. Wire ScrollController into ListView
old2d = """                  child: ListView(
                    padding: const EdgeInsets.all(16),"""
new2d = """                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),"""
if old2d in hist:
    hist = hist.replace(old2d, new2d, 1)
    print('step2d ok: ListView uses ScrollController')
else:
    print('step2d FAILED')

# 2e. Make highlight more visible (stronger teal + left accent bar)
old2e = """    final isHighlighted = _highlightedDay != null && dayNum == _highlightedDay;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? Colors.teal.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isHighlighted
            ? Border.all(color: Colors.teal.shade400, width: 2)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),"""
new2e = """    final isHighlighted = _highlightedDay != null && dayNum == _highlightedDay;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? Colors.teal.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isHighlighted
            ? Border.all(color: Colors.teal.shade600, width: 2.5)
            : null,
        boxShadow: [
          if (isHighlighted)
            BoxShadow(color: Colors.teal.withValues(alpha: 0.25), blurRadius: 10, spreadRadius: 1, offset: const Offset(0, 3))
          else
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),"""
if old2e in hist:
    hist = hist.replace(old2e, new2e, 1)
    print('step2e ok: highlight more visible')
else:
    print('step2e FAILED')

with open('lib/attendance_history_screen.dart', 'w', encoding='utf-8') as f:
    f.write(hist)
print('all patches saved')
