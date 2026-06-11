import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

class VHSExpensesScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;
  final bool isAdmin;

  const VHSExpensesScreen({
    super.key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId,
    this.isAdmin = false,
  });

  @override
  State<VHSExpensesScreen> createState() => _VHSExpensesScreenState();
}

class _VHSExpensesScreenState extends State<VHSExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Tab 1: Apply Petty Cash ─────────────────────────────────────────────────
  final _pcAmountCtrl  = TextEditingController();
  final _pcPurposeCtrl = TextEditingController();
  bool _pcSubmitting = false;

  // ── Tab 2: Submit Expenses ──────────────────────────────────────────────────
  bool _masterLoading = true;
  List<Map<String, dynamic>> _expenseTypes = [];
  List<Map<String, dynamic>> _projectTypes = [];

  Map<String, dynamic>? _selExpType;
  Map<String, dynamic>? _selProject;
  Map<String, dynamic>? _selPettyCash;
  final _expAmountCtrl = TextEditingController();
  final _expDescCtrl   = TextEditingController();
  final _expBillNoCtrl = TextEditingController();
  DateTime _expBillDate = DateTime.now();
  bool _gstOn = false;
  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selCompany;
  File? _billFile;
  bool _expSubmitting = false;
  int _formVersion = 0;

  // ── Tab 3: History ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = false;
  String _historyError = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1 && _masterLoading) _loadMasterData();
        if (_tabController.index == 2) _loadHistory();
      }
    });
    _loadMasterData();
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pcAmountCtrl.dispose();
    _pcPurposeCtrl.dispose();
    _expAmountCtrl.dispose();
    _expDescCtrl.dispose();
    _expBillNoCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<bool> _hasInternet() async {
    final r = await Connectivity().checkConnectivity();
    return r.isNotEmpty && !r.contains(ConnectivityResult.none);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 4 : 3),
    ));
  }

  Future<void> _onWillPop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go Back?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

  // ── Master Data ─────────────────────────────────────────────────────────────

  Future<void> _loadMasterData() async {
    setState(() => _masterLoading = true);
    try {
      final res = await ApiService.fetchMasterData(authToken: widget.authToken);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['status'] == 'success') {
          final data = json['data'] as Map<String, dynamic>? ?? {};
          List<Map<String, dynamic>> toList(dynamic raw) =>
              (raw as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
          // support both nested (json['data']['key']) and top-level (json['key'])
          dynamic get(String key) => data[key] ?? json[key];
          setState(() {
            _expenseTypes = toList(get('expenses_types'));
            _projectTypes = toList(get('project_types'));
            _companies    = toList(get('companies'));

            // Reconcile dropdown selection references to avoid crashes after reloading
            if (_selExpType != null) {
              final match = _expenseTypes.firstWhere(
                (t) => t['id'] == _selExpType!['id'],
                orElse: () => {},
              );
              _selExpType = match.isNotEmpty ? match : null;
            }
            if (_selProject != null) {
              final match = _projectTypes.firstWhere(
                (p) => p['id'] == _selProject!['id'],
                orElse: () => {},
              );
              _selProject = match.isNotEmpty ? match : null;
            }
            if (_selCompany != null) {
              final match = _companies.firstWhere(
                (c) => c['id'] == _selCompany!['id'],
                orElse: () => {},
              );
              _selCompany = match.isNotEmpty ? match : null;
            }
          });
          debugPrint('Master data: expTypes=${_expenseTypes.length}, projects=${_projectTypes.length}, companies=${_companies.length}');
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _masterLoading = false);
    }
  }

  // ── Tab 1: Submit Petty Cash Request ────────────────────────────────────────

  Future<void> _submitPettyCash() async {
    final amount = _pcAmountCtrl.text.trim();
    final purpose = _pcPurposeCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      _showSnack('Enter a valid amount', isError: true); return;
    }
    if (purpose.isEmpty) { _showSnack('Please enter purpose', isError: true); return; }
    if (!await _hasInternet()) { _showSnack('No internet connection', isError: true); return; }

    setState(() => _pcSubmitting = true);
    try {
      final res = await ApiService.applyPettyCash(
        authToken: widget.authToken,
        amount: double.parse(amount),
        purpose: purpose,
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200 && json['status'] == 'success') {
        _showSnack(json['message'] ?? 'Request submitted successfully!');
        _pcAmountCtrl.clear();
        _pcPurposeCtrl.clear();
      } else {
        _showSnack(json['message'] ?? 'Failed to submit', isError: true);
      }
    } catch (_) {
      _showSnack('Network error. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _pcSubmitting = false);
    }
  }

  // ── Tab 2: Submit Expenses ──────────────────────────────────────────────────

  Future<void> _pickBillImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Bill Image', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(leading: const Icon(Icons.camera_alt_rounded, color: Colors.teal), title: const Text('Camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
              ListTile(leading: const Icon(Icons.photo_library_rounded, color: Colors.teal), title: const Text('Gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) setState(() => _billFile = File(picked.path));
  }

  Future<void> _submitExpense() async {
    if (_selExpType == null) { _showSnack('Select expense type', isError: true); return; }
    if (_selProject == null) { _showSnack('Select a project', isError: true); return; }
    if (_expAmountCtrl.text.trim().isEmpty) { _showSnack('Enter amount', isError: true); return; }
    if (_expDescCtrl.text.trim().isEmpty) { _showSnack('Enter description', isError: true); return; }
    if (!await _hasInternet()) { _showSnack('No internet connection', isError: true); return; }

    setState(() => _expSubmitting = true);
    try {
      String base64Image = ' ';
      String fileExt = 'jpg';
      if (_billFile != null) {
        final bytes = await _billFile!.readAsBytes();
        base64Image = base64Encode(bytes);
        fileExt = _billFile!.path.split('.').last.toLowerCase();
      }

      final body = {
        'expenses_type_id': _selExpType!['id'],
        'project_type_id':  _selProject!['id'],
        if (_selPettyCash != null)
          'petty_cash_request_id': _selPettyCash!['id'],
        'gst_applicable':   _gstOn ? 'yes' : 'no',
        'company_id':       widget.companyId,
        if (_gstOn && _selCompany != null)
          'gst_company_id': _selCompany!['id'],
        'details': [
          {
            'bill_number':      _expBillNoCtrl.text.trim(),
            'billnumber1':      _expDescCtrl.text.trim(),
            'bill_date':        DateFormat('yyyy-MM-dd').format(_expBillDate),
            'amount':           double.tryParse(_expAmountCtrl.text.trim()) ?? 0.0,
            'bill_file_base64': base64Image,
            'bill_file_ext':    fileExt,
          }
        ],
      };

      final res = await ApiService.createExpense(authToken: widget.authToken, body: body);
      final json = jsonDecode(res.body);
      if (res.statusCode == 200 && json['status'] == 'success') {
        _showSnack(json['message'] ?? 'Expense submitted successfully!');
        setState(() {
          _formVersion++;
          _selExpType = null;
          _selProject = null;
          _selPettyCash = null;
          _gstOn = false;
          _selCompany = null;
          _billFile = null;
          _expBillDate = DateTime.now();
        });
        _expAmountCtrl.clear();
        _expDescCtrl.clear();
        _expBillNoCtrl.clear();
      } else {
        _showSnack(json['message'] ?? 'Failed to submit expense', isError: true);
      }
    } catch (_) {
      _showSnack('Network error. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _expSubmitting = false);
    }
  }

  // ── Tab 3: History ──────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    setState(() { _historyLoading = true; _historyError = ''; });
    try {
      final res = await ApiService.fetchPettyCashHistory(authToken: widget.authToken);
      final json = jsonDecode(res.body);
      if (res.statusCode == 200 && json['status'] == 'success') {
        setState(() {
          _history = (json['requests'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          // Reconcile dropdown selection reference to avoid assertion crashes
          if (_selPettyCash != null) {
            final match = _history.firstWhere(
              (h) => h['id'] == _selPettyCash!['id'],
              orElse: () => {},
            );
            _selPettyCash = match.isNotEmpty ? match : null;
          }
        });
      } else {
        setState(() => _historyError = json['message'] ?? 'Failed to load');
      }
    } catch (_) {
      setState(() => _historyError = 'Network error. Pull to retry.');
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onWillPop(); },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.teal.shade700,
          elevation: 0,
          title: const Text('Expenses', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _onWillPop,
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.teal.shade200,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 20), text: 'Apply Cash'),
              Tab(icon: Icon(Icons.receipt_long_rounded, size: 20), text: 'Submit Bills'),
              Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildApplyCashTab(),
            _buildSubmitBillsTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  // ── Tab 1 Widget ─────────────────────────────────────────────────────────────

  Widget _buildApplyCashTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade700, Colors.teal.shade400],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 36),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Petty Cash Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('Request advance cash for work expenses', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Form
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Requested Amount (₹) *'),
                _numField(ctrl: _pcAmountCtrl, hint: 'e.g. 5000', icon: Icons.currency_rupee_rounded),
                const SizedBox(height: 16),
                _sectionTitle('Purpose *'),
                TextField(
                  controller: _pcPurposeCtrl,
                  maxLines: 3,
                  decoration: _dec('Describe why you need this cash', Icons.notes_rounded),
                ),
                const SizedBox(height: 24),
                _submitBtn(
                  label: 'Submit Request',
                  loading: _pcSubmitting,
                  icon: Icons.send_rounded,
                  color: Colors.teal.shade700,
                  onTap: _submitPettyCash,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _infoCard(Icons.info_outline_rounded, Colors.blue,
              'Your request will be reviewed and approved by management before disbursement.'),
        ],
      ),
    );
  }

  // ── Tab 2 Widget ─────────────────────────────────────────────────────────────

  Widget _buildSubmitBillsTab() {
    if (_masterLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    return RefreshIndicator(
      color: Colors.teal,
      onRefresh: _loadMasterData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade700, Colors.teal.shade400],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: Colors.white, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Submit Expense Bills', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 4),
                        Text('Upload bills and claim reimbursement', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Expense Type
                  _sectionTitle('Expense Type *'),
                  DropdownMenu<Map<String, dynamic>>(
                    key: ValueKey('expType_$_formVersion'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: false,
                    initialSelection: _selExpType,
                    label: const Text('Select Expense Type'),
                    leadingIcon: const Icon(Icons.category_rounded, color: Colors.teal, size: 20),
                    dropdownMenuEntries: _expenseTypes.map((t) {
                      return DropdownMenuEntry<Map<String, dynamic>>(
                        value: t,
                        label: t['name']?.toString() ?? '',
                      );
                    }).toList(),
                    onSelected: (v) => setState(() => _selExpType = v),
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.teal, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Project
                  _sectionTitle('Project *'),
                  DropdownMenu<Map<String, dynamic>>(
                    key: ValueKey('project_$_formVersion'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: false,
                    initialSelection: _selProject,
                    label: const Text('Select Project'),
                    leadingIcon: const Icon(Icons.work_rounded, color: Colors.teal, size: 20),
                    dropdownMenuEntries: _projectTypes.map((t) {
                      return DropdownMenuEntry<Map<String, dynamic>>(
                        value: t,
                        label: t['name']?.toString() ?? '',
                      );
                    }).toList(),
                    onSelected: (v) => setState(() => _selProject = v),
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.teal, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Link to Petty Cash Request
                  _sectionTitle('Link Petty Cash Request (Optional)'),
                  DropdownMenu<Map<String, dynamic>>(
                    key: ValueKey('pettyCash_$_formVersion'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: false,
                    initialSelection: _selPettyCash,
                    label: const Text('Select Petty Cash Request'),
                    leadingIcon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.teal, size: 20),
                    dropdownMenuEntries: _history.map((h) {
                      final amount = h['requested_amount']?.toString() ?? '0';
                      final status = h['status_label']?.toString() ?? '';
                      String dateStr = '';
                      try {
                        dateStr = DateFormat('dd MMM yy').format(DateTime.parse(h['created_at']?.toString() ?? ''));
                      } catch (_) {}
                      return DropdownMenuEntry<Map<String, dynamic>>(
                        value: h,
                        label: '₹$amount — $status ($dateStr)',
                      );
                    }).toList(),
                    onSelected: (v) => setState(() => _selPettyCash = v),
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.teal, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // GST toggle (OFF by default for VHS)
                  Row(
                    children: [
                      const Icon(Icons.receipt_rounded, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      const Text('GST Applicable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Switch(
                        value: _gstOn,
                        activeThumbColor: Colors.purple,
                        activeTrackColor: Colors.teal.withValues(alpha: 0.4),
                        onChanged: (v) => setState(() {
                          _gstOn = v;
                          if (!v) _selCompany = null;
                        }),
                      ),
                      Text(_gstOn ? 'Yes' : 'No',
                          style: TextStyle(color: _gstOn ? Colors.purple : Colors.grey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  // Company dropdown — visible only when GST is ON
                  if (_gstOn) ...[
                    const SizedBox(height: 12),
                    _sectionTitle('Company *'),
                    DropdownMenu<Map<String, dynamic>>(
                      key: ValueKey('company_$_formVersion'),
                      expandedInsets: EdgeInsets.zero,
                      requestFocusOnTap: false,
                      initialSelection: _selCompany,
                      label: const Text('Select Company'),
                      leadingIcon: const Icon(Icons.business_rounded, color: Colors.teal, size: 20),
                      dropdownMenuEntries: _companies.map((c) {
                        return DropdownMenuEntry<Map<String, dynamic>>(
                          value: c,
                          label: c['name']?.toString() ?? '',
                        );
                      }).toList(),
                      onSelected: (v) => setState(() => _selCompany = v),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.teal, width: 1.5)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Bill Date
                  _sectionTitle('Bill Date *'),
                  GestureDetector(
                    onTap: () async {
                      final dt = await showDatePicker(
                        context: context,
                        initialDate: _expBillDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (dt != null) setState(() => _expBillDate = dt);
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: DateFormat('dd MMM yyyy').format(_expBillDate),
                        ),
                        decoration: _dec('Bill Date', Icons.calendar_today_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bill Number
                  _sectionTitle('Bill Number'),
                  TextField(controller: _expBillNoCtrl, decoration: _dec('Bill No. (optional)', Icons.tag_rounded)),
                  const SizedBox(height: 16),

                  // Description
                  _sectionTitle('Description *'),
                  TextField(controller: _expDescCtrl, decoration: _dec('Description', Icons.notes_rounded)),
                  const SizedBox(height: 16),

                  // Amount
                  _sectionTitle('Amount (₹) *'),
                  _numField(ctrl: _expAmountCtrl, hint: 'Enter amount', icon: Icons.currency_rupee_rounded),
                  const SizedBox(height: 16),

                  // Bill Photo
                  _sectionTitle('Bill Photo (optional)'),
                  GestureDetector(
                    onTap: _pickBillImage,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _billFile != null ? Colors.purple : Colors.grey.shade200,
                          width: _billFile != null ? 1.5 : 1,
                        ),
                      ),
                      child: _billFile != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.file(_billFile!, fit: BoxFit.cover)),
                                Positioned(
                                  top: 6, right: 6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _billFile = null),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_rounded, color: Colors.grey.shade400, size: 32),
                                const SizedBox(height: 6),
                                Text('Tap to add bill photo', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _submitBtn(
                    label: 'Submit Expense Claim',
                    loading: _expSubmitting,
                    icon: Icons.send_rounded,
                    color: Colors.teal.shade700,
                    onTap: _submitExpense,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 3 Widget ─────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    final Widget emptyWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.teal.shade100),
          const SizedBox(height: 16),
          Text('No History Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('No petty cash requests found', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );

    if (_historyError.isNotEmpty || _history.isEmpty) return emptyWidget;

    return RefreshIndicator(
      color: Colors.teal,
      onRefresh: _loadHistory,
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
              // Table header
              Container(
                decoration: BoxDecoration(
                  color: Colors.teal.shade700,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: const [
                    _TableCell(text: '#', isHeader: true, flex: 1),
                    _TableCell(text: 'Date', isHeader: true, flex: 3),
                    _TableCell(text: 'Amount', isHeader: true, flex: 2),
                    _TableCell(text: 'Status', isHeader: true, flex: 3),
                  ],
                ),
              ),
              // Table rows
              ...List.generate(_history.length, (i) {
                final item   = _history[i];
                final amount = item['requested_amount']?.toString() ?? '0';
                final statusLabel = item['status_label']?.toString() ?? 'Pending';
                final createdAt   = item['created_at']?.toString() ?? '';

                String dateStr = '-';
                try {
                  dateStr = DateFormat('dd MMM yy').format(DateTime.parse(createdAt));
                } catch (_) {}

                final sl = statusLabel.toLowerCase();
                Color statusColor;
                if (sl.contains('approved') || sl.contains('disbursed')) {
                  statusColor = Colors.green;
                } else if (sl.contains('rejected')) {
                  statusColor = Colors.red;
                } else if (sl.contains('pending')) {
                  statusColor = Colors.orange;
                } else {
                  statusColor = Colors.blue;
                }

                final isEven = i % 2 == 0;
                return Container(
                  decoration: BoxDecoration(
                    color: isEven ? Colors.grey.shade50 : Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    borderRadius: i == _history.length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(16))
                        : BorderRadius.zero,
                  ),
                  child: Row(
                    children: [
                      _TableCell(text: '${i + 1}', flex: 1),
                      _TableCell(text: dateStr, flex: 3),
                      _TableCell(text: '₹${double.tryParse(amount)?.toStringAsFixed(0) ?? amount}', flex: 2),
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold),
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

  // ── Shared UI helpers ─────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600, letterSpacing: 0.3)),
    );
  }

  Widget _numField({required TextEditingController ctrl, required String hint, required IconData icon}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      decoration: _dec(hint, icon),
    );
  }

  Widget _submitBtn({required String label, required bool loading, required IconData icon, required Color color, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: loading ? null : onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                loading ? 'Submitting...' : label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) {
    return InputDecoration(
      labelText: hint,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.teal, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.teal, width: 1.5)),
    );
  }

  Widget _infoCard(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final int flex;

  const _TableCell({required this.text, this.isHeader = false, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: isHeader ? 12 : 13,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.white : Colors.black87,
          ),
          textAlign: isHeader ? TextAlign.center : TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
