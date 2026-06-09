import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'check_in_out_screen.dart';
import 'work_update_screen.dart';

class MoreScreen extends StatelessWidget {
  final String authToken;
  final String empId;
  final String empName;
  final String deviceSerialNumber;
  final String companyId;
  final bool isAdmin;

  const MoreScreen({
    super.key,
    required this.authToken,
    required this.empId,
    required this.empName,
    required this.deviceSerialNumber,
    required this.companyId,
    this.isAdmin = false,
  });

  /// Check internet connectivity
  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  /// Show no internet dialog
  void _showNoInternetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text("No Internet"),
        content: Text("Please check your internet connection."),
      ),
    );
  }

  /// Back press handler
  Future<bool> _onWillPop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go Back?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!await _hasInternet()) {
      if (context.mounted) _showNoInternetDialog(context);
      return false;
    }
    if (!context.mounted) return false;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInOutScreen(
          empName: empName,
          empId: empId,
          authToken: authToken,
          deviceSerialNumber: deviceSerialNumber,
          companyId: companyId,
          isAdmin: isAdmin,
        ),
      ),
      (route) => false,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ COMPANY CHECK
    if (companyId == "6") {
      return _buildWorkUpdateUI(context);
    } else {
      return _buildFeatureNotAvailableUI(context);
    }
  }

  // ─────────────────────────────────────────────
  // ✅ WORK UPDATE UI (Company ID = 6)
  // ─────────────────────────────────────────────
  Widget _buildWorkUpdateUI(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onWillPop(context); },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text("Work Update"),
          backgroundColor: Colors.green,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: const Icon(Icons.assignment, color: Colors.green),
                  ),
                  title: const Text(
                    "Daily Work Update",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text("Enter today’s work details"),
                  trailing:
                  const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    if (!await _hasInternet()) {
                      if (context.mounted) _showNoInternetDialog(context);
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkUpdateScreen(
                          empId: empId,
                          empName: empName,
                          authToken: authToken,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 3,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child:
                    const Icon(Icons.list_alt, color: Colors.orange),
                  ),
                  title: const Text(
                    "View Work History",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text("Coming soon"),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("History Feature Coming Soon"),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ❌ FEATURE NOT AVAILABLE UI (Other companies)
  // ─────────────────────────────────────────────
  Widget _buildFeatureNotAvailableUI(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onWillPop(context); },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.block,
                    size: 100,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Feature Not Available",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "This feature is not available for your company.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Go Back"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => _onWillPop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
