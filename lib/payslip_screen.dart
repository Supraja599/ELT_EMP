import 'package:flutter/material.dart';

class PayslipScreen extends StatefulWidget {
  const PayslipScreen({Key? key}) : super(key: key);

  @override
  _PayslipScreenState createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  final List<Map<String, String>> payslips = [
    {"month": "July", "year": "2025"},
    {"month": "August", "year": "2025"},
    {"month": "September", "year": "2025"},
  ];

  void _downloadPayslip(String month, String year) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Downloading $month $year payslip..."),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // TODO: Add your actual PDF download logic here
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("My Payslips"),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: payslips.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.receipt_long,
                  size: 100, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                "No Payslips Available",
                style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                "Your payslips will appear here once available.",
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
            : ListView.separated(
          itemCount: payslips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final slip = payslips[index];
            return Card(
              elevation: 4,
              shadowColor: Colors.blue.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.blue.shade50,
                  child: const Icon(Icons.picture_as_pdf,
                      color: Colors.blue, size: 28),
                ),
                title: Text(
                  slip['month']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  slip['year']!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () => _downloadPayslip(
                    slip['month']!,
                    slip['year']!,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text("Download"),
                ),
                onTap: () => _downloadPayslip(
                  slip['month']!,
                  slip['year']!,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
