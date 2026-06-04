import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class OtLateRequestScreen extends StatefulWidget {
  final String empId;
  final String authToken;
  final String empName;

  const OtLateRequestScreen({
    super.key,
    required this.empId,
    required this.authToken,
    required this.empName,
  });

  @override
  State<OtLateRequestScreen> createState() => _OtLateRequestScreenState();
}

class _OtLateRequestScreenState extends State<OtLateRequestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Submit form state
  String _requestType = 'late_checkin';
  final _dateController = TextEditingController();
  final _reasonController = TextEditingController();
  final _durationController = TextEditingController();
  bool _isSubmitting = false;

  // My requests state
  List<Map<String, dynamic>> _myRequests = [];
  bool _isLoadingRequests = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _fetchMyRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateController.dispose();
    _reasonController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final response = await ApiService.fetchOtRequests(
        empId: widget.empId,
        authToken: widget.authToken,
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final List raw = data['requests'] ?? [];
        setState(() {
          _myRequests = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    setState(() => _isLoadingRequests = false);
  }

  Future<void> _submitRequest() async {
    if (_reasonController.text.trim().isEmpty) {
      _showSnack('Please enter a reason', isError: true);
      return;
    }
    if (_requestType == 'overtime' && _durationController.text.trim().isEmpty) {
      _showSnack('Please enter OT duration (e.g. 02:30)', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiService.submitOtRequest(
        empId: widget.empId,
        authToken: widget.authToken,
        requestType: _requestType,
        date: _dateController.text,
        reason: _reasonController.text.trim(),
        duration: _requestType == 'overtime'
            ? _durationController.text.trim()
            : '00:00',
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _reasonController.clear();
        _durationController.clear();
        _showSnack(data['message'] ?? 'Request submitted. Your manager will be notified.');
        await _fetchMyRequests();
        _tabController.animateTo(1);
      } else {
        _showSnack(data['message'] ?? 'Failed to submit request', isError: true);
      }
    } catch (_) {
      _showSnack('Network error. Please try again.', isError: true);
    }
    setState(() => _isSubmitting = false);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.orange;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'late_checkin': return Icons.schedule_rounded;
      case 'early_checkout': return Icons.exit_to_app_rounded;
      case 'overtime': return Icons.star_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'late_checkin': return Colors.orange;
      case 'early_checkout': return Colors.deepOrange;
      case 'overtime': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'late_checkin': return 'Late Check-In';
      case 'early_checkout': return 'Early Check-Out';
      case 'overtime': return 'Overtime (OT)';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'OT / Late Requests',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.teal,
          labelColor: Colors.teal,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Submit'),
            Tab(icon: Icon(Icons.list_alt_rounded), text: 'My Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSubmitTab(),
          _buildMyRequestsTab(),
        ],
      ),
    );
  }

  // ── Submit Tab ─────────────────────────────────────────────────────────────
  Widget _buildSubmitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.teal, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Submit requests for Late Check-in, Early Check-out, or Overtime for manager approval.',
                    style: TextStyle(fontSize: 13, color: Colors.teal),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Form card
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
                const Text(
                  'Request Details',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Request type selector
                const Text('Request Type', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _typeChip('late_checkin', 'Late In', Icons.schedule_rounded, Colors.orange),
                    const SizedBox(width: 8),
                    _typeChip('early_checkout', 'Early Out', Icons.exit_to_app_rounded, Colors.deepOrange),
                    const SizedBox(width: 8),
                    _typeChip('overtime', 'Overtime', Icons.star_rounded, Colors.purple),
                  ],
                ),
                const SizedBox(height: 20),

                // Date
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 7)),
                    );
                    if (picked != null) {
                      _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _dateController,
                      decoration: _inputDecoration('Date', Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Duration (OT only)
                if (_requestType == 'overtime') ...[
                  TextField(
                    controller: _durationController,
                    decoration: _inputDecoration('OT Duration (HH:MM, e.g. 02:30)', Icons.timer_rounded),
                    keyboardType: TextInputType.datetime,
                  ),
                  const SizedBox(height: 16),
                ],

                // Reason
                TextField(
                  controller: _reasonController,
                  maxLines: 4,
                  decoration: _inputDecoration('Reason *', Icons.chat_bubble_outline_rounded),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : _submitRequest,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit for Approval',
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
        ],
      ),
    );
  }

  Widget _typeChip(String value, String label, IconData icon, Color color) {
    final isSelected = _requestType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _requestType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  // ── My Requests Tab ────────────────────────────────────────────────────────
  Widget _buildMyRequestsTab() {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    if (_myRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No requests submitted yet', style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 8),
            const Text(
              'Your submitted OT / late requests\nwill appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchMyRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myRequests.length,
        itemBuilder: (ctx, i) => _buildRequestCard(_myRequests[i]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final type = req['request_type']?.toString() ?? '';
    final date = req['date']?.toString() ?? '';
    final reason = req['reason']?.toString() ?? '';
    final status = req['status']?.toString() ?? 'pending';
    final duration = req['duration']?.toString() ?? '';
    final remarks = req['remarks']?.toString() ?? '';
    final createdAt = req['created_at']?.toString() ?? '';

    DateTime? parsedDate;
    try { parsedDate = DateTime.parse(date); } catch (_) {}
    final displayDate = parsedDate != null
        ? DateFormat('dd MMM yyyy').format(parsedDate)
        : date;

    final typeColor = _typeColor(type);
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon(type), color: typeColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _typeLabel(type),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: typeColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(displayDate, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    if (duration.isNotEmpty && duration != '00:00') ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.timer_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(duration, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                    if (createdAt.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        'Submitted: ${_formatCreatedAt(createdAt)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(reason, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                if (remarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.person_rounded, size: 14, color: statusColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Manager: $remarks',
                            style: TextStyle(fontSize: 12, color: statusColor, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCreatedAt(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('dd MMM').format(dt);
    } catch (_) {
      return raw;
    }
  }
}
