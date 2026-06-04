import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class WorkUpdateScreen extends StatefulWidget {
  final String empId;
  final String empName;
  final String authToken;

  const WorkUpdateScreen({
    super.key,
    required this.empId,
    required this.empName,
    required this.authToken,
  });

  @override
  State<WorkUpdateScreen> createState() => _WorkUpdateScreenState();
}

class _WorkUpdateScreenState extends State<WorkUpdateScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _visitedDateController = TextEditingController();
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _mailController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _headCountController = TextEditingController();
  final TextEditingController _nextActionController = TextEditingController();
  final TextEditingController _programController = TextEditingController();
  final TextEditingController _nextVisitDateController =
  TextEditingController();

  String? _selectedNextAction;
  String? _selectedProgramAvailable;

  String todayDate = DateFormat('dd-MM-yyyy').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _visitedDateController.text = todayDate;
    _getCurrentLocation();
  }

  // ================= LOCATION =================
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack("Please enable location services");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark p = placemarks.first;
        String address = [
          p.name,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
          p.country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        setState(() => _locationController.text = address);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  // ================= INTERNET =================
  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  // ================= SUBMIT =================
  void _submitWork() async {
    if (!await _hasInternet()) {
      _showSnack("No internet connection");
      return;
    }

    if (_formKey.currentState!.validate()) {

      final Map<String, dynamic> body = {
        "auth_token": widget.authToken,
        "date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "school_name": _schoolNameController.text.trim(),
        "location": _locationController.text.trim(),
        "contact_no": _contactController.text.trim(),
        "mail_communication": _mailController.text.trim(),
        "remarks": _remarksController.text.trim(),
        "head_count": int.tryParse(_headCountController.text) ?? 0,
        "next_action": _nextActionController.text.trim(),
        "program_available": _programController.text.trim(),
        "employee_name": widget.empName,
        "employee_id": widget.empId,
      };

      // ✅ SEND visit_date ONLY FOR "Visit Again"
      if (_selectedNextAction == "Visit Again") {
        body["visit_date"] = DateFormat('yyyy-MM-dd').format(
          DateFormat('dd-MM-yyyy').parse(_nextVisitDateController.text),
        );
      }

      try {
        final response = await ApiService.submitWorkUpdate(
          body: body,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          _showSnack("Work update submitted successfully");
          _clearFields();
        } else {
          _showSnack("Failed: ${response.body}");
        }
      } catch (e) {
        _showSnack("Error: $e");
      }
    }
  }

  // ================= CLEAR =================
  void _clearFields() {
    _schoolNameController.clear();
    _contactController.clear();
    _mailController.clear();
    _remarksController.clear();
    _headCountController.clear();
    _visitedDateController.text = todayDate;

    setState(() {
      _selectedNextAction = null;
      _selectedProgramAvailable = null;
      _nextActionController.clear();
      _programController.clear();
      _nextVisitDateController.clear();
    });

    _getCurrentLocation();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text("Work Sheet Entry"),
        backgroundColor: Colors.green,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label("Employee"),
                _readOnlyField(widget.empName),
                const SizedBox(height: 16),

                _label("Visited Date"),
                TextFormField(
                  controller: _visitedDateController,
                  readOnly: true,
                  decoration: _inputDecoration(hint: "dd-mm-yyyy"),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      _visitedDateController.text =
                          DateFormat('dd-MM-yyyy').format(picked);
                    }
                  },
                ),

                const SizedBox(height: 16),
                _label("School Name"),
                TextFormField(
                  controller: _schoolNameController,
                  validator: (v) => v!.isEmpty ? "Enter school name" : null,
                  decoration: _inputDecoration(hint: "Enter school name"),
                ),

                const SizedBox(height: 16),
                _label("Location"),
                TextFormField(
                  controller: _locationController,
                  readOnly: true,
                  decoration: _inputDecoration(hint: "Location").copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location),
                      onPressed: _getCurrentLocation,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _label("Contact No"),
                TextFormField(
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(hint: "Enter contact no"),
                ),

                const SizedBox(height: 16),
                _label("Mail Communication"),
                TextFormField(
                  controller: _mailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(hint: "Enter email"),
                ),

                const SizedBox(height: 16),
                _label("Remarks"),
                TextFormField(
                  controller: _remarksController,
                  decoration: _inputDecoration(hint: "Enter remarks"),
                ),

                const SizedBox(height: 16),
                _label("Head Count"),
                TextFormField(
                  controller: _headCountController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(hint: "Enter head count"),
                ),
                const SizedBox(height: 16),
                _label("Next Action"),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedNextAction,
                  decoration: _inputDecoration(hint: "Select next action"),
                  items: const [
                    DropdownMenuItem(
                        value: "Visit Again", child: Text("Visit Again")),
                    DropdownMenuItem(
                        value: "No Visit", child: Text("No Visit")),
                    DropdownMenuItem(
                        value: "Action Required",
                        child: Text("Action Required")),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedNextAction = value;
                      _nextActionController.text = value ?? "";
                      if (value != "Visit Again") {
                        _nextVisitDateController.clear();
                      }
                    });
                  },
                  validator: (value) =>
                  value == null ? "Please select next action" : null,
                ),

                if (_selectedNextAction == "Visit Again") ...[
                  const SizedBox(height: 16),
                  _label("Next Visit Date"),
                  TextFormField(
                    controller: _nextVisitDateController,
                    readOnly: true,
                    decoration:
                    _inputDecoration(hint: "Select next visit date"),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate:
                        DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        _nextVisitDateController.text =
                            DateFormat('dd-MM-yyyy').format(picked);
                      }
                    },
                    validator: (value) {
                      if (_selectedNextAction == "Visit Again" &&
                          (value == null || value.isEmpty)) {
                        return "Please select next visit date";
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 16),
                _label("Program Available"),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedProgramAvailable,
                  decoration:
                  _inputDecoration(hint: "Select program availability"),
                  items: const [
                    DropdownMenuItem(value: "Yes", child: Text("Yes")),
                    DropdownMenuItem(value: "No", child: Text("No")),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedProgramAvailable = value;
                      _programController.text = value ?? "";
                    });
                  },
                  validator: (value) =>
                  value == null ? "Please select Yes or No" : null,
                ),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitWork,
                    child: const Text(
                      "SUBMIT WORK SHEET",
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= HELPERS =================
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child:
    Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _readOnlyField(String value) => Container(
    padding: const EdgeInsets.all(14),
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(value),
  );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}
