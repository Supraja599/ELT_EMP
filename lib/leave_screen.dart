import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

class LeaveScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;
  final bool isAdmin;

  const LeaveScreen({
    super.key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId,
    this.isAdmin = false,
  });

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  // ── Apply Leave ────────────────────────────────────────────────────────────
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String? selectedLeaveTypeId;
  bool _isSubmitting = false;
  final Set<String> _submittedLeaves = {};
  String? _quotaWarning;
  bool _checkingQuota = false;

  final List<Map<String, String>> leaveTypes = [
    {"id": "1", "label": "Casual Leave"},
    {"id": "2", "label": "Comp Off Leave"},
    {"id": "3", "label": "Earned Leave"},
  ];

  // ── Leave Balance ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _leaveBalance;
  bool _isLoadingBalance = false;

  // ── Leave History ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _leaveBalance == null) {
        _fetchLeaveBalance();
      }
      if (_tabController.index == 2 && _leaveHistory.isEmpty) {
        _fetchLeaveHistory();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  Future<bool> _onWillPop() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go Back?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
        ],
      ),
    );
    if (!mounted) return false;
    if (exit == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CheckInOutScreen(
            empId: widget.empId,
            empName: widget.empName,
            authToken: widget.authToken,
            companyId: widget.companyId,
            deviceSerialNumber: widget.deviceSerialNumber,
            isAdmin: widget.isAdmin,
          ),
        ),
        (route) => false,
      );
    }
    return false;
  }

  // ── Apply Leave helpers ────────────────────────────────────────────────────

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      // Check quota when both dates are set
      if (_fromDateController.text.isNotEmpty && _toDateController.text.isNotEmpty) {
        _checkDeptQuota();
      }
    }
  }

  Future<void> _checkDeptQuota() async {
    if (_fromDateController.text.isEmpty || _toDateController.text.isEmpty) return;
    setState(() { _checkingQuota = true; _quotaWarning = null; });
    try {
      final response = await ApiService.fetchDeptLeaveQuota(
        empId: widget.empId,
        authToken: widget.authToken,
        fromDate: _fromDateController.text,
        toDate: _toDateController.text,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final onLeave = data['employees_on_leave'] ?? 0;
        final maxAllowed = data['max_allowed'] ?? 0;
        if (onLeave >= maxAllowed && maxAllowed > 0) {
          setState(() {
            _quotaWarning = 'Warning: $onLeave colleague(s) from your department already have leave on these dates. Manager approval may be required.';
          });
        }
      }
    } catch (_) {}
    setState(() => _checkingQuota = false);
  }

  Future<void> _submitLeave() async {
    if (_isSubmitting) return;

    if (!await _hasInternet()) {
      _showDialog('No Internet', 'Please check your internet connection.');
      return;
    }

    if (_fromDateController.text.isEmpty ||
        _toDateController.text.isEmpty ||
        selectedLeaveTypeId == null ||
        _reasonController.text.isEmpty) {
      _showDialog('Incomplete Form', 'Please fill all fields.');
      return;
    }

    final fromDate = DateTime.parse(_fromDateController.text);
    final toDate = DateTime.parse(_toDateController.text);

    if (fromDate.isAfter(toDate)) {
      _showDialog('Invalid Dates', 'From date cannot be after To date.');
      return;
    }

    final leaveKey = '${widget.empId}_${_fromDateController.text}_${_toDateController.text}_$selectedLeaveTypeId';
    if (_submittedLeaves.contains(leaveKey)) {
      _showDialog('Duplicate', 'Leave already submitted for these dates.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiService.applyLeave(
        authToken: widget.authToken,
        empId: widget.empId,
        leaveTypeId: selectedLeaveTypeId!,
        fromDate: _fromDateController.text,
        toDate: _toDateController.text,
        reason: _reasonController.text,
      );
      final result = jsonDecode(response.body);
      if (result['status'] == 'success') {
        _submittedLeaves.add(leaveKey);

        // Save this leave to local phone storage so History tab shows it immediately
        await _saveLeaveLocally({
          'id': result['leave_id']?.toString() ??
              'local_${DateTime.now().millisecondsSinceEpoch}',
          'leave_type':      _leaveTypeName(selectedLeaveTypeId!),
          'leave_type_name': _leaveTypeName(selectedLeaveTypeId!),
          'from_date':   _fromDateController.text,
          'to_date':     _toDateController.text,
          'total_days':  _daysBetween(_fromDateController.text, _toDateController.text),
          'reason':      _reasonController.text,
          'status':      'pending',
          'applied_on':  DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });

        _fromDateController.clear();
        _toDateController.clear();
        _reasonController.clear();
        setState(() { selectedLeaveTypeId = null; _quotaWarning = null; });
        _showDialog('Success', result['message'] ?? 'Leave applied successfully. Your manager will be notified.');
        // Refresh history and balance
        _fetchLeaveHistory();
        _fetchLeaveBalance();
      } else {
        _showDialog('Failed', result['message'] ?? 'Something went wrong.');
      }
    } catch (_) {
      _showDialog('Error', 'Could not submit leave. Please try again.');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  // ── Balance & History ──────────────────────────────────────────────────────

  String get _localCacheKey => 'leave_history_${widget.empId}';

  /// Saves a newly applied leave into the phone's local storage.
  Future<void> _saveLeaveLocally(Map<String, dynamic> leave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCacheKey);
      final List<Map<String, dynamic>> existing = raw != null
          ? (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
      // Prepend so newest is first
      existing.insert(0, leave);
      await prefs.setString(_localCacheKey, jsonEncode(existing));
    } catch (_) {}
  }

  /// Loads all locally cached leaves from the phone.
  Future<List<Map<String, dynamic>>> _loadLocalLeaveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCacheKey);
      if (raw != null && raw.isNotEmpty) {
        return (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Returns the display name for a leave type id.
  String _leaveTypeName(String id) {
    final found = leaveTypes.firstWhere(
      (t) => t['id'] == id,
      orElse: () => {'label': 'Leave'},
    );
    return found['label'] ?? 'Leave';
  }

  /// Calculates number of days between two date strings (inclusive).
  int _daysBetween(String from, String to) {
    try {
      return DateTime.parse(to).difference(DateTime.parse(from)).inDays + 1;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _fetchLeaveBalance() async {
    setState(() => _isLoadingBalance = true);
    try {
      final response = await ApiService.fetchLeaveBalance(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() => _leaveBalance = data['balance'] ?? data);
      }
    } catch (_) {}
    setState(() => _isLoadingBalance = false);
  }

  Future<void> _fetchLeaveHistory() async {
    setState(() => _isLoadingHistory = true);

    // Step 1 — Show local cache instantly while API loads
    final local = await _loadLocalLeaveHistory();
    if (local.isNotEmpty && mounted) {
      setState(() => _leaveHistory = local);
    }

    // Step 2 — Try the backend API
    try {
      final response = await ApiService.fetchLeaveHistory(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final List raw = data['leaves'] ?? data['history'] ?? [];
        if (mounted) {
          final apiLeaves = raw
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          // API is authoritative — update display and overwrite local cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_localCacheKey, jsonEncode(apiLeaves));
          setState(() => _leaveHistory = apiLeaves);
        }
      }
    } catch (_) {
      // API not available — already showing local cache, nothing to do
    }

    setState(() => _isLoadingHistory = false);
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onWillPop(); },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text(
            'Leave Management',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
            onPressed: _onWillPop,
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.teal,
            labelColor: Colors.teal,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.send_rounded, size: 18), text: 'Apply'),
              Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 18), text: 'Balance'),
              Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildApplyTab(),
            _buildBalanceTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Apply ───────────────────────────────────────────────────────────

  Widget _buildApplyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quota warning
          if (_checkingQuota)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Checking department availability...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
          if (_quotaWarning != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _quotaWarning!,
                      style: const TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Form card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leave Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // From date
                TextField(
                  controller: _fromDateController,
                  readOnly: true,
                  decoration: _inputDecoration('From Date', Icons.calendar_today_rounded),
                  onTap: () => _selectDate(context, _fromDateController),
                ),
                const SizedBox(height: 16),

                // To date
                TextField(
                  controller: _toDateController,
                  readOnly: true,
                  decoration: _inputDecoration('To Date', Icons.calendar_today_rounded),
                  onTap: () => _selectDate(context, _toDateController),
                ),
                const SizedBox(height: 16),

                DropdownMenu<String>(
                  initialSelection: leaveTypes.any((t) => t['id'] == selectedLeaveTypeId)
                      ? selectedLeaveTypeId
                      : null,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  label: const Text('Select Leave Type'),
                  leadingIcon: const Icon(Icons.category_rounded, color: Colors.teal, size: 20),
                  dropdownMenuEntries: leaveTypes.map((type) {
                    return DropdownMenuEntry<String>(
                      value: type['id']!,
                      label: type['label']!,
                      leadingIcon: Icon(_leaveTypeIcon(type['id']!), color: Colors.teal, size: 18),
                    );
                  }).toList(),
                  onSelected: (v) => setState(() => selectedLeaveTypeId = v),
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.teal, width: 1.5),
                    ),
                    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),

                // Reason
                TextField(
                  controller: _reasonController,
                  maxLines: 4,
                  decoration: _inputDecoration('Reason for Leave *', Icons.chat_bubble_outline_rounded),
                ),
                const SizedBox(height: 24),

                // Submit
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitLeave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit Leave Request',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Balance ─────────────────────────────────────────────────────────

  Widget _buildBalanceTab() {
    if (_isLoadingBalance) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    if (_leaveBalance == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Leave balance not loaded', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchLeaveBalance,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('Load Balance', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // Support both flat map and nested 'types' list from API
    final List<Map<String, dynamic>> balanceItems = [];
    if (_leaveBalance!.containsKey('balances')) {
      final balances = _leaveBalance!['balances'];
      if (balances is Map<String, dynamic>) {
        balances.forEach((key, val) {
          String displayName = key.replaceAll('_', ' ').split(' ').map((word) {
            if (word.isEmpty) return '';
            return word[0].toUpperCase() + word.substring(1);
          }).join(' ');

          // Match Leave Type ID for icons
          String typeId = '1';
          if (key.toLowerCase().contains('comp')) {
            typeId = '2';
          } else if (key.toLowerCase().contains('earned')) {
            typeId = '3';
          }

          balanceItems.add({
            'name': displayName,
            'balance': val,
            'total': 0.0,
            'id': typeId,
          });
        });
      }
    } else if (_leaveBalance!.containsKey('types')) {
      final List raw = _leaveBalance!['types'] ?? [];
      balanceItems.addAll(raw.map((e) => Map<String, dynamic>.from(e)));
    } else {
      // Flat keys like casual_leave_balance, earned_leave_balance …
      final leaveMap = {
        'Casual Leave': _leaveBalance!['casual_leave_balance'] ?? _leaveBalance!['cl_balance'],
        'Earned Leave': _leaveBalance!['earned_leave_balance'] ?? _leaveBalance!['el_balance'],
        'Comp Off': _leaveBalance!['comp_off_balance'] ?? _leaveBalance!['comp_leave_balance'],
        'Sick Leave': _leaveBalance!['sick_leave_balance'] ?? _leaveBalance!['sl_balance'],
      };
      leaveMap.forEach((name, balance) {
        if (balance != null) {
          balanceItems.add({
            'name': name,
            'balance': balance,
            'total': _leaveBalance!['${name.toLowerCase().replaceAll(' ', '_')}_total'],
            'id': name.toLowerCase().contains('casual') ? '1' : (name.toLowerCase().contains('comp') ? '2' : '3'),
          });
        }
      });
    }

    return RefreshIndicator(
      onRefresh: _fetchLeaveBalance,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Available Leave Balance',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'As of ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (balanceItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: Text('No leave balance data available', style: TextStyle(color: Colors.grey))),
            )
          else
            ...balanceItems.map((item) => _buildBalanceCard(item)),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(Map<String, dynamic> item) {
    final name = item['leave_type_name']?.toString() ?? item['name']?.toString() ?? 'Leave';
    final balance = double.tryParse(item['balance']?.toString() ?? item['available']?.toString() ?? '0') ?? 0;
    final total = double.tryParse(item['total']?.toString() ?? item['total_days']?.toString() ?? '0') ?? 0;
    final used = double.tryParse(item['used']?.toString() ?? '0') ?? (total - balance);
    final pct = total > 0 ? (balance / total).clamp(0.0, 1.0) : 0.0;

    Color barColor;
    if (total > 0) {
      if (pct > 0.5) {
        barColor = Colors.green;
      } else if (pct > 0.25) {
        barColor = Colors.orange;
      } else {
        barColor = Colors.red;
      }
    } else {
      barColor = balance > 0 ? Colors.teal : Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _leaveTypeIcon(item['id']?.toString() ?? ''),
                      color: barColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: balance.toStringAsFixed(balance == balance.roundToDouble() ? 0 : 1),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: barColor),
                    ),
                    if (total > 0)
                      TextSpan(
                        text: ' / ${total.toStringAsFixed(0)} days',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Available: ${balance.toStringAsFixed(0)} days', style: TextStyle(fontSize: 12, color: barColor)),
                Text('Used: ${used.toStringAsFixed(0)} days', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Available: ${balance.toStringAsFixed(balance == balance.roundToDouble() ? 0 : 1)} days',
              style: TextStyle(fontSize: 12, color: barColor, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 3: History ─────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    if (_leaveHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No leave history found', style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchLeaveHistory,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('Refresh', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchLeaveHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              // Header
              Container(
                decoration: BoxDecoration(
                  color: Colors.teal.shade700,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: const [
                    _LvCell(text: 'From', isHeader: true, flex: 3),
                    _LvCell(text: 'To', isHeader: true, flex: 3),
                    _LvCell(text: 'Type', isHeader: true, flex: 3),
                    _LvCell(text: 'Status', isHeader: true, flex: 3),
                  ],
                ),
              ),
              // Rows
              ...List.generate(_leaveHistory.length, (i) {
                final leave = _leaveHistory[i];
                final fromDate = leave['from_date']?.toString() ?? leave['leave_from']?.toString() ?? '';
                final toDate   = leave['to_date']?.toString()   ?? leave['leave_to']?.toString()   ?? '';
                final type     = leave['leave_type']?.toString() ?? leave['leave_type_name']?.toString() ?? 'Leave';
                final status   = leave['status']?.toString() ?? 'pending';
                final statusColor = _leaveStatusColor(status);

                String fmt(String d) {
                  try { return DateFormat('dd MMM yy').format(DateTime.parse(d)); } catch (_) { return d; }
                }

                final isEven = i % 2 == 0;
                return Container(
                  decoration: BoxDecoration(
                    color: isEven ? Colors.grey.shade50 : Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    borderRadius: i == _leaveHistory.length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(16))
                        : BorderRadius.zero,
                  ),
                  child: Row(
                    children: [
                      _LvCell(text: fmt(fromDate), flex: 3),
                      _LvCell(text: fmt(toDate), flex: 3),
                      _LvCell(text: type, flex: 3),
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _leaveStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'cancelled': return Colors.grey;
      default: return Colors.orange;
    }
  }

  IconData _leaveTypeIcon(String id) {
    switch (id) {
      case '1': return Icons.beach_access_rounded;
      case '2': return Icons.coffee_rounded;
      case '3': return Icons.stars_rounded;
      default: return Icons.event_note_rounded;
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.teal, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.teal, width: 1.5),
      ),
    );
  }
}

class _LvCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final int flex;

  const _LvCell({required this.text, this.isHeader = false, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Text(
          text,
          style: TextStyle(
            fontSize: isHeader ? 11 : 12,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
