import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'check_in_out_screen.dart';
import 'services/api_service.dart';

class ExpensesScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;
  final bool isAdmin;

  const ExpensesScreen({
    super.key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId,
    this.isAdmin = false,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {

  // ── Master data ────────────────────────────────────────────────────────────
  bool _masterLoading = true;
  List<Map<String, dynamic>> _expenseTypes = [];
  List<Map<String, dynamic>> _projectTypes = [];
  List<Map<String, dynamic>> _fuelTypes    = [];
  List<Map<String, dynamic>> _companies    = [];

  // ── Form state ─────────────────────────────────────────────────────────────
  Map<String, dynamic>? _selExpenseType;
  Map<String, dynamic>? _selProjectType;
  Map<String, dynamic>? _selFuelType;
  Map<String, dynamic>? _selCompany;

  bool _isFuelExpense = false;  // toggled automatically when fuel type selected
  bool _gstApplicable = false;
  int  _formVersion   = 0;     // incrementing forces dropdowns to reset initialValue

  final _billNumberCtrl    = TextEditingController();
  final _descriptionCtrl   = TextEditingController();
  final _amountCtrl        = TextEditingController();
  final _startKmCtrl       = TextEditingController();
  final _endKmCtrl         = TextEditingController();
  final _authorizedByCtrl  = TextEditingController();

  DateTime _billDate = DateTime.now();
  File? _billFile;
  bool _isSubmitting = false;

  // ── Overlay dropdown for Project Search ────────────────────────────────────
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _projectFieldKey = GlobalKey();
  final _projectSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _filteredProjectsForDropdown = [];

  @override
  void initState() {
    super.initState();
    _loadMasterData();
  }

  @override
  void dispose() {
    _closeDropdownOverlay();
    _billNumberCtrl.dispose();
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    _startKmCtrl.dispose();
    _endKmCtrl.dispose();
    _authorizedByCtrl.dispose();
    _projectSearchCtrl.dispose();
    super.dispose();
  }

  // ── Master Data ────────────────────────────────────────────────────────────

  Future<void> _loadMasterData() async {
    setState(() => _masterLoading = true);
    try {
      final response = await ApiService.fetchMasterData(
        authToken: widget.authToken,
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'success') {
          final data = json['data'] as Map<String, dynamic>? ?? {};

          List<Map<String, dynamic>> toList(dynamic raw) =>
              (raw as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

          setState(() {
            _expenseTypes = toList(data['expenses_types']);
            _projectTypes = toList(data['project_types']);
            _fuelTypes    = toList(data['fuel_types']);
            _companies    = toList(data['companies']);
          });
        } else {
          _showSnack('Could not load expense types: ${json['message'] ?? ''}', isError: true);
        }
      } else {
        _showSnack('Server error ${response.statusCode}. Pull down to retry.', isError: true);
      }
    } catch (e) {
      _showSnack('Network error loading master data. Check connection.', isError: true);
    } finally {
      setState(() => _masterLoading = false);
    }
  }

  // ── Back navigation ────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    _closeDropdownOverlay();
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go Back?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('Yes')),
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

  // ── Internet check ─────────────────────────────────────────────────────────

  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  // ── Image picker ───────────────────────────────────────────────────────────

  Future<void> _pickBillImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Bill Image', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Colors.teal),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.teal),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() => _billFile = File(picked.path));
    }
  }

  void _showDropdownOverlay() {
    _closeDropdownOverlay();
    
    _filteredProjectsForDropdown = _projectTypes;
    _projectSearchCtrl.clear();
    
    final RenderBox? renderBox = _projectFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setOverlayState) {
            void onSearchChanged() {
              final query = _projectSearchCtrl.text.trim().toLowerCase();
              setOverlayState(() {
                if (query.isEmpty) {
                  _filteredProjectsForDropdown = _projectTypes;
                } else {
                  _filteredProjectsForDropdown = _projectTypes.where((p) {
                    final name = (p['name'] ?? '').toString().toLowerCase();
                    return name.contains(query);
                  }).toList();
                }
              });
            }
            
            return Stack(
              children: [
                GestureDetector(
                  onTap: _closeDropdownOverlay,
                  behavior: HitTestBehavior.translucent,
                  child: Container(),
                ),
                Positioned(
                  width: size.width,
                  child: CompositedTransformFollower(
                    link: _layerLink,
                    showWhenUnlinked: false,
                    offset: Offset(0, size.height + 4),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextField(
                                controller: _projectSearchCtrl,
                                autofocus: true,
                                onChanged: (_) => onSearchChanged(),
                                decoration: InputDecoration(
                                  hintText: 'Search project...',
                                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.teal, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Colors.teal, width: 1.2),
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1, thickness: 1),
                            Flexible(
                              child: _filteredProjectsForDropdown.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                        'No projects found',
                                        style: TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: _filteredProjectsForDropdown.length,
                                      itemBuilder: (ctx, index) {
                                        final project = _filteredProjectsForDropdown[index];
                                        final isSelected = _selProjectType != null &&
                                            _selProjectType!['id'] == project['id'];
                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selProjectType = project;
                                            });
                                            _closeDropdownOverlay();
                                          },
                                          child: Container(
                                            color: isSelected ? Colors.teal.shade50 : null,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    project['name']?.toString() ?? '',
                                                    style: TextStyle(
                                                      color: isSelected ? Colors.teal.shade800 : Colors.black87,
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                ),
                                                if (isSelected)
                                                  const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 16),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeDropdownOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Validation
    if (_selExpenseType == null) { _showSnack('Please select an expense type', isError: true); return; }
    if (_selProjectType == null) { _showSnack('Please select a project',        isError: true); return; }
    if (_amountCtrl.text.trim().isEmpty) { _showSnack('Please enter amount',    isError: true); return; }
    if (_descriptionCtrl.text.trim().isEmpty) { _showSnack('Please enter description', isError: true); return; }

    if (_isFuelExpense) {
      if (_selFuelType == null)           { _showSnack('Please select fuel type',     isError: true); return; }
      if (_startKmCtrl.text.trim().isEmpty) { _showSnack('Please enter starting KM', isError: true); return; }
      if (_endKmCtrl.text.trim().isEmpty)   { _showSnack('Please enter ending KM',   isError: true); return; }
      if (_authorizedByCtrl.text.trim().isEmpty) { _showSnack('Please enter authorized by', isError: true); return; }
    } else {
      if (_selCompany == null)            { _showSnack('Please select a company',     isError: true); return; }
    }

    if (!await _hasInternet()) {
      _showSnack('No internet connection. Please check and retry.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Convert image to base64 if provided
      String base64Image = ' ';
      String fileExt = 'jpg';
      if (_billFile != null) {
        final bytes = await _billFile!.readAsBytes();
        base64Image = base64Encode(bytes);
        fileExt = _billFile!.path.split('.').last.toLowerCase();
      }

      final billDateStr = DateFormat('yyyy-MM-dd').format(_billDate);

      Map<String, dynamic> body;

      if (_isFuelExpense) {
        // ── Fuel expense body ──────────────────────────────────────────────
        body = {
          'expenses_type_id': _selExpenseType!['id'],
          'project_type_id':  _selProjectType!['id'],
          'gst_applicable':   'no',
          'fuel_type_id':     _selFuelType!['id'],
          'details': [
            {
              'bill_date':     billDateStr,
              'billnumber1':   _descriptionCtrl.text.trim(),
              'amount':        double.tryParse(_amountCtrl.text.trim()) ?? 0.0,
              'started_km':    int.tryParse(_startKmCtrl.text.trim()) ?? 0,
              'ended_km':      int.tryParse(_endKmCtrl.text.trim()) ?? 0,
              'authorized_by': _authorizedByCtrl.text.trim(),
              'bill_file_base64': base64Image,
              'bill_file_ext':    fileExt,
            }
          ],
        };
      } else {
        // ── Normal expense body ────────────────────────────────────────────
        body = {
          'expenses_type_id': _selExpenseType!['id'],
          'project_type_id':  _selProjectType!['id'],
          'gst_applicable':   _gstApplicable ? 'yes' : 'no',
          'company_id':       _selCompany!['id'].toString(),
          'details': [
            {
              'bill_number':      _billNumberCtrl.text.trim(),
              'billnumber1':      _descriptionCtrl.text.trim(),
              'bill_date':        billDateStr,
              'amount':           double.tryParse(_amountCtrl.text.trim()) ?? 0.0,
              'bill_file_base64': base64Image,
              'bill_file_ext':    fileExt,
            }
          ],
        };
      }

      final response = await ApiService.createExpense(
        authToken: widget.authToken,
        body: body,
      );

      final json = jsonDecode(response.body);

      if (response.statusCode == 200 && json['status'] == 'success') {
        _showSnack(json['message'] ?? 'Expense submitted successfully!');
        _clearForm();
      } else {
        _showSnack(json['message'] ?? 'Failed to submit expense.', isError: true);
      }
    } catch (e) {
      _showSnack('Error submitting expense. Please try again.', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _clearForm() {
    _closeDropdownOverlay();
    setState(() {
      _formVersion++;           // forces all DropdownButtonFormField to rebuild from initialValue: null
      _selExpenseType   = null;
      _selProjectType   = null;
      _selFuelType      = null;
      _selCompany       = null;
      _isFuelExpense    = false;
      _gstApplicable    = false;
      _billFile         = null;
      _billDate         = DateTime.now();
    });
    _billNumberCtrl.clear();
    _descriptionCtrl.clear();
    _amountCtrl.clear();
    _startKmCtrl.clear();
    _endKmCtrl.clear();
    _authorizedByCtrl.clear();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 4 : 3),
    ));
  }

  InputDecoration _dec(String label, IconData icon) {
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
            'Expense Claim',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _onWillPop,
          ),
          actions: [
            if (_masterLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Reload master data',
                onPressed: _loadMasterData,
              ),
          ],
        ),
        body: _masterLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.teal),
                    SizedBox(height: 16),
                    Text('Loading expense categories...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadMasterData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Fuel / Normal toggle banner ─────────────────────
                      if (_isFuelExpense)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_gas_station_rounded, color: Colors.orange),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Fuel / Travel expense form active',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _isFuelExpense = false;
                                  _selFuelType = null;
                                }),
                                child: const Text('Switch', style: TextStyle(color: Colors.orange)),
                              ),
                            ],
                          ),
                        ),

                      // ── Form card ───────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.receipt_long_rounded, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Text(
                                  'Submit Expense Claim',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // 1. Expense Type
                            _sectionLabel('Expense Type *'),
                            DropdownMenu<Map<String, dynamic>>(
                              key: ValueKey('expType_$_formVersion'),
                              initialSelection: _selExpenseType,
                              expandedInsets: EdgeInsets.zero,
                              requestFocusOnTap: false,
                              label: const Text('Select Expense Type'),
                              leadingIcon: const Icon(Icons.category_rounded, color: Colors.teal, size: 20),
                              dropdownMenuEntries: _expenseTypes.map((t) {
                                return DropdownMenuEntry<Map<String, dynamic>>(
                                  value: t,
                                  label: t['name']?.toString() ?? '',
                                );
                              }).toList(),
                              onSelected: (v) {
                                setState(() {
                                  _selExpenseType = v;
                                  // Auto-detect fuel expense by name
                                  final name = (v?['name'] ?? '').toString().toLowerCase();
                                  _isFuelExpense = name.contains('fuel') ||
                                      name.contains('petrol') ||
                                      name.contains('diesel') ||
                                      name.contains('travel') ||
                                      name.contains('transport');
                                  if (!_isFuelExpense) _selFuelType = null;
                                });
                              },
                              inputDecorationTheme: InputDecorationTheme(
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.teal, width: 1.5)),
                                labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. Project
                            _sectionLabel('Project *'),
                            CompositedTransformTarget(
                              link: _layerLink,
                              child: GestureDetector(
                                key: _projectFieldKey,
                                onTap: _showDropdownOverlay,
                                child: InputDecorator(
                                  decoration: _dec('Select Project', Icons.work_rounded).copyWith(
                                    suffixIcon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.teal, size: 28),
                                  ),
                                  child: Text(
                                    _selProjectType != null 
                                        ? _selProjectType!['name']?.toString() ?? '' 
                                        : 'Select Project',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _selProjectType != null ? Colors.black87 : Colors.grey.shade600,
                                      fontWeight: _selProjectType != null ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 3a. Company (normal expense only)
                            if (!_isFuelExpense) ...[
                              _sectionLabel('Company *'),
                              DropdownMenu<Map<String, dynamic>>(
                                key: ValueKey('company_$_formVersion'),
                                initialSelection: _selCompany,
                                expandedInsets: EdgeInsets.zero,
                                requestFocusOnTap: false,
                                label: const Text('Select Company'),
                                leadingIcon: const Icon(Icons.business_rounded, color: Colors.teal, size: 20),
                                dropdownMenuEntries: _companies.map((c) {
                                  return DropdownMenuEntry<Map<String, dynamic>>(
                                    value: c,
                                    label: c['company_name']?.toString() ?? '',
                                  );
                                }).toList(),
                                onSelected: (v) => setState(() => _selCompany = v),
                                inputDecorationTheme: InputDecorationTheme(
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.teal, width: 1.5)),
                                  labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 3b. GST Applicable
                              Row(
                                children: [
                                  const Icon(Icons.receipt_rounded, color: Colors.teal, size: 20),
                                  const SizedBox(width: 8),
                                  const Text('GST Applicable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  Switch(
                                    value: _gstApplicable,
                                    activeThumbColor: Colors.teal,
                                    activeTrackColor: Colors.teal.withValues(alpha: 0.4),
                                    onChanged: (v) => setState(() => _gstApplicable = v),
                                  ),
                                  Text(
                                    _gstApplicable ? 'Yes' : 'No',
                                    style: TextStyle(
                                      color: _gstApplicable ? Colors.teal : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 3c. Fuel Type (fuel expense only)
                            if (_isFuelExpense) ...[
                              _sectionLabel('Fuel Type *'),
                              DropdownMenu<Map<String, dynamic>>(
                                key: ValueKey('fuel_$_formVersion'),
                                initialSelection: _selFuelType,
                                expandedInsets: EdgeInsets.zero,
                                requestFocusOnTap: false,
                                label: const Text('Select Fuel Type'),
                                leadingIcon: const Icon(Icons.local_gas_station_rounded, color: Colors.teal, size: 20),
                                dropdownMenuEntries: _fuelTypes.map((f) {
                                  return DropdownMenuEntry<Map<String, dynamic>>(
                                    value: f,
                                    label: f['name']?.toString() ?? '',
                                  );
                                }).toList(),
                                onSelected: (v) => setState(() => _selFuelType = v),
                                inputDecorationTheme: InputDecorationTheme(
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.teal, width: 1.5)),
                                  labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 4. Bill Date
                            _sectionLabel('Bill Date *'),
                            GestureDetector(
                              onTap: () async {
                                final dt = await showDatePicker(
                                  context: context,
                                  initialDate: _billDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (dt != null) setState(() => _billDate = dt);
                              },
                              child: AbsorbPointer(
                                child: TextField(
                                  readOnly: true,
                                  controller: TextEditingController(
                                    text: DateFormat('dd MMM yyyy').format(_billDate),
                                  ),
                                  decoration: _dec('Bill Date', Icons.calendar_today_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 5. Bill Number (normal only)
                            if (!_isFuelExpense) ...[
                              _sectionLabel('Bill Number'),
                              TextField(
                                controller: _billNumberCtrl,
                                decoration: _dec('Bill Number (e.g. BILL123)', Icons.tag_rounded),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 6. Description
                            _sectionLabel('Description *'),
                            TextField(
                              controller: _descriptionCtrl,
                              decoration: _dec('Description', Icons.notes_rounded),
                            ),
                            const SizedBox(height: 16),

                            // 7. Amount
                            _sectionLabel('Amount (₹) *'),
                            TextField(
                              controller: _amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              decoration: _dec('Amount', Icons.currency_rupee_rounded),
                            ),
                            const SizedBox(height: 16),

                            // 8. Fuel-specific fields
                            if (_isFuelExpense) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _sectionLabel('Starting KM *'),
                                        TextField(
                                          controller: _startKmCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: _dec('Start KM', Icons.speed_rounded),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _sectionLabel('Ending KM *'),
                                        TextField(
                                          controller: _endKmCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: _dec('End KM', Icons.speed_rounded),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _sectionLabel('Authorized By *'),
                              TextField(
                                controller: _authorizedByCtrl,
                                decoration: _dec('Manager / Authorized Person Name', Icons.person_rounded),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 9. Bill image
                            _sectionLabel('Bill Photo (optional)'),
                            GestureDetector(
                              onTap: _pickBillImage,
                              child: Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _billFile != null
                                        ? Colors.teal
                                        : Colors.grey.shade200,
                                    width: _billFile != null ? 1.5 : 1,
                                  ),
                                ),
                                child: _billFile != null
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(11),
                                            child: Image.file(_billFile!, fit: BoxFit.cover),
                                          ),
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () => setState(() => _billFile = null),
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo_rounded,
                                              color: Colors.grey.shade400, size: 32),
                                          const SizedBox(height: 6),
                                          Text('Tap to add bill photo',
                                              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Submit button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _isSubmitting ? null : _submit,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, color: Colors.white),
                                label: Text(
                                  _isSubmitting ? 'Submitting...' : 'Submit Expense Claim',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Info cards ──────────────────────────────────────
                      _infoCard(
                        icon: Icons.info_outline_rounded,
                        color: Colors.blue,
                        text: 'After submission, your expense claim will be reviewed by management.',
                      ),
                      const SizedBox(height: 10),
                      _infoCard(
                        icon: Icons.local_gas_station_rounded,
                        color: Colors.orange,
                        text: 'For fuel/travel expenses: selecting a fuel-related expense type auto-activates the KM fields.',
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _infoCard({required IconData icon, required Color color, required String text}) {
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
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}


